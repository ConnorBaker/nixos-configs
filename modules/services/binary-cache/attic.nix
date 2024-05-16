{ config, pkgs, ... }:
let
  inherit (config.services.binary-cache) domain;
  # Named after their paths in secrets.yaml.
  user = "atticd";
  atticdCredentials = "${user}/${domain}/credentials.env";
in
{
  environment.systemPackages = [ pkgs.attic ];

  # NOTE: File should have:
  # - ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64
  sops.secrets.${atticdCredentials} = {
    owner = user;
    mode = "0440";
    path = "/var/lib/${atticdCredentials}";
    sopsFile = ./secrets.yaml;
  };

  services.atticd = {
    enable = true;

    credentialsFile = config.sops.secrets.${atticdCredentials}.path;

    settings = {
      listen = "[::]:5000";

      # The API endpoint _must_ end with a slash (e.g., `https://domain.tld/attic/`
      # not `https://domain.tld/attic`).
      api-endpoint = "https://direct.${domain}/";
      allowed-hosts = [
        "direct.${domain}"
        domain
      ];

      database.url = "postgresql://${user}@localhost:5432/attic";

      # Our settings are slightly larger than upstream as we prefer larger chunks.
      chunking =
        let
          # A kilobyte is 1024 bytes.
          KB = 1024;
          # A megabyte is 1024 kilobytes.
          MB = 1024 * KB;
        in
        {
          min-size = 16 * KB;
          nar-size-threshold = 64 * KB;
          avg-size = 256 * KB;
          max-size = 1 * MB;
        };

      # Use ZSTD for compression
      compression.type = "zstd";

      # Use local storage
      storage = {
        type = "local";
        path = "/var/lib/${user}/storage";
      };
    };
  };

  # TODO: "/var/lib/atticd" -- should disable ZFS compression because the contents are already compressed
  systemd.services.atticd = {
    serviceConfig = {
      # Our user is persistent (so we can use SOPS to manage secrets).
      DynamicUser = pkgs.lib.mkForce false;
      # Log everything
      Environment = [
        "RUST_LOG=debug"
        "RUST_BACKTRACE=1"
      ];
    };
  };

  # TODO: The module should handle this for us.
  users = {
    groups.${user} = { };
    users.${user} = {
      description = "${user} user";
      group = user;
      home = "/var/lib/${user}";
      isSystemUser = true;
    };
  };
}
