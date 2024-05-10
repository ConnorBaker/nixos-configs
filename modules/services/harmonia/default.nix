{ config, ... }:
let
  domain = "cantcache.me";
  cantCacheMeSigningKey = "harmonia/${domain}.key";
in
{
  # NOTE: generate a public/private key pair like this:
  # $ nix-store --generate-binary-cache-key cantcache.me-1 cantcache.me.key cantcache.me.pub
  sops.secrets.${cantCacheMeSigningKey} = {
    owner = "harmonia";
    mode = "0440";
    path = "/var/lib/${cantCacheMeSigningKey}";
    sopsFile = ./secrets.yaml;
  };

  services.harmonia = {
    enable = false;
    signKeyPath = config.sops.secrets.${cantCacheMeSigningKey}.path;

    settings = {
      # default ip:hostname to bind to
      bind = "[::]:5000";
      # Sets number of workers to start in the webserver
      workers = 24;
      # Sets the per-worker maximum number of concurrent connections.
      max_connection_rate = 16 * 1024;
      # binary cache priority that is advertised in /nix-cache-info
      priority = 30;
    };
  };
}
