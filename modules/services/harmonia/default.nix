{ config, pkgs, ... }:
let
  domain = "cantcache.me";
  cantCacheMeCloudflareKey = "acme/${domain}/credentials.env";
  cantCacheMeSigningKey = "harmonia/${domain}.key";
in
{
  sops.secrets = {
    # Must contain the following:
    # CLOUDFLARE_EMAIL=...
    # CLOUDFLARE_DNS_API_TOKEN=...
    # Then, add an AAAA DNS record to Cloudflare with the public IPv6 address of the host
    ${cantCacheMeCloudflareKey} = {
      owner = "acme";
      mode = "0440";
      path = "/var/lib/${cantCacheMeCloudflareKey}";
      sopsFile = ./secrets.yaml;
    };
    # NOTE: generate a public/private key pair like this:
    # $ nix-store --generate-binary-cache-key cantcache.me-1 cantcache.me.key cantcache.me.pub
    ${cantCacheMeSigningKey} = {
      owner = "harmonia";
      mode = "0440";
      path = "/var/lib/${cantCacheMeSigningKey}";
      sopsFile = ./secrets.yaml;
    };
  };

  networking.firewall.allowedTCPPorts = [ 443 ];

  security.acme = {
    acceptTerms = true;
    preliminarySelfsigned = false;

    certs.${domain} = {
      inherit domain;
      dnsPropagationCheck = true;
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      email = "connorbaker01@gmail.com";
      environmentFile = config.sops.secrets.${cantCacheMeCloudflareKey}.path;
      extraDomainNames = [ "*.${domain}" ];
      reloadServices = [ "nginx" ];
      webroot = null;
    };
  };

  services = {
    harmonia = {
      enable = true;
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
    nginx = {
      enable = true;
      package = pkgs.nginxMainline;
      additionalModules = [ pkgs.nginxModules.brotli ];

      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      # By default we have only one process.
      appendConfig = ''
        worker_processes auto;
      '';

      virtualHosts.${domain} = {
        useACMEHost = domain;
        forceSSL = true;
        kTLS = true;
        # Log to syslog
        extraConfig = ''
          error_log syslog:server=unix:/dev/log;
          access_log syslog:server=unix:/dev/log combined;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:5000";
          proxyWebsockets = true;
          # Compress everything with brotli, as well as we are able to.
          extraConfig = ''
            brotli on;
            brotli_comp_level 11;
            brotli_min_length 0;
            brotli_window 16m;
            brotli_static on;
            brotli_types *;
          '';
        };
      };
    };
  };

  # Allow nginx access to letsencrypt keys
  users.users."nginx".extraGroups = [ "acme" ];
}
