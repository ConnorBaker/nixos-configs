{ config, pkgs, ... }:
let
  domain = "cantcache.me";
  cantCacheMeCloudflareKey = "acme/${domain}/credentials.env";
in
{
  # Must contain the following:
  # CLOUDFLARE_EMAIL=...
  # CLOUDFLARE_DNS_API_TOKEN=...
  # Then, add an AAAA DNS record to Cloudflare with the public IPv6 address of the host
  sops.secrets.${cantCacheMeCloudflareKey} = {
    owner = "acme";
    mode = "0440";
    path = "/var/lib/${cantCacheMeCloudflareKey}";
    sopsFile = ./secrets.yaml;
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

  services.nginx = {
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
        extraConfig =
          # Don't limit the size of the client body.
          ''
            client_max_body_size 0;
          ''
          # Compress everything with brotli, as well as we are able to.
          + ''
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

  # Allow nginx access to letsencrypt keys
  users.users."nginx".extraGroups = [ "acme" ];
}
