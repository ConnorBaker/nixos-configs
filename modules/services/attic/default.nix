{ config, lib, pkgs, ... }:
let
  inherit (lib.modules) mkForce;
  # Named after their paths in secrets.yaml.
  # NOTE: The directory is atticd, not attic
  atticCredentials = "atticd/credentials.env";
in
{
  environment.systemPackages = [ config.services.atticd.package pkgs.attic ];

  # TODO: "/var/lib/postgresql"
  # TODO: "/var/lib/atticd"
  # TODO: ZFS should have a separate dataset for the database
  #
  # Steps:
  # 1. Create token with:
  # sudo atticd-atticadm make-token --sub attic-cuda-test --validity 1y --pull attic-cuda-test --push attic-cuda-test --delete attic-cuda-test --create-cache attic-cuda-test --configure-cache attic-cuda-test --configure-cache-retention attic-cuda-test --destroy-cache attic-cuda-test
  # 2. Log in to the server:
  # attic login local http://localhost:8083 <token from previous step>
  # 3. Create the cache:
  # attic cache create attic-cuda-test
  # 4. Push to the cache:
  # attic push attic-cuda-test ./result
  # 5. Set up to use the cache:
  # attic use attic-cuda-test
  networking.firewall.allowedTCPPorts = [ 8083 ];
  systemd.services.atticd.serviceConfig.Environment = [
    "RUST_LOG=debug"
    "RUST_BACKTRACE=1"
  ];

  # NOTE: File should have:
  # - ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64
  # - ACCESS_KEY_ID
  # - SECRET_ACCESS_KEY
  sops.secrets.${atticCredentials} = {
    owner = "attic";
    mode = "0440";
    path = "/var/lib/${atticCredentials}";
    sopsFile = ./secrets.yaml;
  };

  services = {
    atticd = {
      enable = true;

      credentialsFile = config.sops.secrets.${atticCredentials}.path;

      # Change user and group from atticd to attic to match the name of the table and user
      # in postgresql
      user = "attic";
      group = "attic";

      settings = {
        listen = "[::]:8083";

        # Allowed `Host` headers
        #
        # This _must_ be configured for production use. If unconfigured or the
        # list is empty, all `Host` headers are allowed.
        # allowed-hosts = [];

        database.url = "postgresql://attic:attic@localhost:5432/attic";

        # TODO: This is where attic is expected to be hosted/available; for now, that's on localhost
        # The canonical API endpoint of this server
        #
        # This is the endpoint exposed to clients in `cache-config` responses.
        #
        # This _must_ be configured for production use. If not configured, the
        # API endpoint is synthesized from the client's `Host` header which may
        # be insecure.
        #
        # The API endpoint _must_ end with a slash (e.g., `https://domain.tld/attic/`
        # not `https://domain.tld/attic`).
        # api-endpoint = "https://cantcache.me/";

        # Data chunking
        #
        # Warning: If you change any of the values here, it will be
        # difficult to reuse existing chunks for newly-uploaded NARs
        # since the cutpoints will be different. As a result, the
        # deduplication ratio will suffer for a while after the change.
        chunking = {
          # The minimum NAR size to trigger chunking
          #
          # If 0, chunking is disabled entirely for newly-uploaded NARs.
          # If 1, all NARs are chunked.
          nar-size-threshold = 64 * 1024; # 64 KiB

          # The preferred minimum size of a chunk, in bytes
          min-size = 16 * 1024; # 16 KiB

          # The preferred average size of a chunk, in bytes
          avg-size = 64 * 1024; # 64 KiB

          # The preferred maximum size of a chunk, in bytes
          max-size = 256 * 1024; # 256 KiB
        };

        # TODO: Copying from R2 is *excruciatingly* slow and the API costs are high given the small chunk size.
        compression = {
          type = "zstd";
          level = 19;
        };

        storage = {
          type = "s3";
          endpoint = "https://b10fa25202b183e3807763a0b0320d47.r2.cloudflarestorage.com";
          region = "us-east-1";
          bucket = "attic-cuda-test";
        };
      };
    };
    postgresql = {
      enable = true;
      enableTCPIP = true;

      ensureDatabases = [ "attic" ];
      ensureUsers = [
        {
          name = "attic";
          ensureDBOwnership = true;
        }
      ];

      # TODO: We should be able to cut this down to the minimum necessary
      authentication = ''
        # Allow the attic user to access the database
        #
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   attic           attic                                   trust
        host    attic           attic           127.0.0.1/32            trust
        host    attic           attic           ::1/128                 trust
        host    attic           attic           localhost               trust
      '';

      settings = {
        log_connections = true;
        log_destination = mkForce "syslog";
        log_disconnections = true;
        log_statement = "all";
        logging_collector = true;
        port = 5432;
      };
    };
  };

  users.users.attic = {
    description = "Attic account";
    extraGroups = [ "wheel" ];
    isNormalUser = true;
  };
}
