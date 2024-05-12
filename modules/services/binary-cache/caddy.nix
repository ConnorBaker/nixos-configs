{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services.binary-cache) domain;
  cloudflareCredentials = "caddy/${domain}/credentials.env";
  inherit (lib.attrsets) genAttrs;
  inherit (lib.trivial) const;
in
{
  networking.firewall = {
    allowedTCPPorts = [ 443 ];
    allowedUDPPorts = [ 443 ];
  };

  services.caddy = {
    enable = true;
    email = "connorbaker01@gmail.com";

    # Use to avoid rate limits while testing
    # TODO: Set back to null after the rate limit resets
    acmeCA = lib.warn ''
      USING LETSENCRYPT STAGING ENDPOINT
      This is only for testing purposes and should not be used in production.
    '' "https://acme-staging-v02.api.letsencrypt.org/directory";

    package = pkgs.caddy-with-cloudflare-dns;

    globalConfig = ''
      debug
      admin off
    '';

    # Create different virtual hosts for each domain.
    # It's important that we don't use aliases here, as we want to ensure that the domain is
    # always set to the same value as the key in the virtualHosts attribute set.
    # Cloudflare proxies the traffic to cantcache.me, but not to direct.cantcache.me,
    # so we need to create a separate virtual host for the direct subdomain.
    virtualHosts =
      let
        extraConfig =
          # Our TLS is done through Cloudflare
          ''
            tls {
              dns cloudflare {env.CLOUDFLARE_DNS_API_TOKEN}
              resolvers 1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001
            }
          ''
          # Try to compress all responses so long as they're larger than the default 512 bytes,
          # with a preference for zstd over gzip
          + ''
            encode zstd gzip {
              match header Content-Type *
            }
          ''
          # Use the reverse_proxy directive to forward requests to the backend server on port 5000
          + ''
            reverse_proxy :5000
          '';
        domains = [
          "direct.${domain}"
          domain
        ];
        mkConfig = const { inherit extraConfig; };
      in
      genAttrs domains mkConfig;
  };

  # Must contain the following:
  # CLOUDFLARE_DNS_API_TOKEN=...
  # NOTE: This token must have DNS:Edit and Zone:Read permissions.
  # Then, add an AAAA DNS record to Cloudflare with the public IPv6 address of the host
  sops.secrets.${cloudflareCredentials} = {
    owner = "caddy";
    mode = "0440";
    path = "/var/lib/${cloudflareCredentials}";
    sopsFile = ./secrets.yaml;
  };

  # Use systemd's EnvironmentFile to set the CLOUDFLARE_DNS_API_TOKEN
  systemd.services.caddy = {
    # We need to create the directory caddy uses to store cached certificates and ensure it has
    # execute permissions so it can be accessed by the caddy user
    # TODO: This should be handled for us -- why is caddy creating nested directories without the executable bit?
    preStart = ''
      mkdir -p /var/lib/caddy/.local/share/caddy
      chown -R caddy:caddy /var/lib/caddy
      chmod -R 700 /var/lib/caddy
    '';
    serviceConfig.EnvironmentFile = config.sops.secrets.${cloudflareCredentials}.path;
  };
}
