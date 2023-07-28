{
  config,
  lib,
  ...
}: let
  grafanaDomain = config.services.grafana.settings.server.domain;
in {
  networking.firewall.allowedTCPPorts = [443];

  services = {
    grafana.settings = {
      server = {
        enforce_domain = true;
        domain = "nixos-desktop.rove-hexatonic.ts.net";
        cert_file = "${./certs/${grafanaDomain}.crt}";
        cert_key = config.sops.secrets."tailscale/${grafanaDomain}.key".path;
        protocol = "https";
      };
      security = {
        admin_email = "connorbaker01@gmail.com";
        admin_password = "$__file{${config.sops.secrets."grafana/admin_password".path}}";
        admin_user = "connorbaker";
        content_security_policy = true;
        cookie_secure = true;
        cookie_samesite = "strict";
        strict_transport_security = true;
        strict_transport_security_preload = true;
      };
    };

    nginx.virtualHosts.${grafanaDomain} = {
      forceSSL = true;
      sslCertificate = "${./certs/${grafanaDomain}.crt}";
      sslCertificateKey = config.sops.secrets."tailscale/${grafanaDomain}.key".path;
    };

    prometheus = {
      globalConfig = {
        evaluation_interval = "30s";
        scrape_interval = "30s";
        scrape_timeout = "10s";
      };
      exporters.node.disabledCollectors = [
        "btrfs"
        "xfs"
      ];
    };
  };

  sops = {
    age.sshKeyPaths = ["/home/connorbaker/.ssh/id_ed25519"];
    secrets = {
      "grafana/admin_password" = {
        owner = config.users.users.grafana.name;
        group = config.users.users.grafana.group;
        restartUnits = ["grafana.service"];
        sopsFile = ./secrets/grafana.yaml;
      };
      "tailscale/${grafanaDomain}.key" = {
        group = config.users.groups.keys.name;
        # The default mode is 0400, which does not allow the keys group to read it.
        # https://github.com/Mic92/sops-nix/blob/c36df4fe4bf4bb87759b1891cab21e7a05219500/modules/sops/default.nix#L53
        mode = "0440";
        restartUnits = [
          "grafana.service"
          "nginx.service"
        ];
        sopsFile = ./secrets/tailscale.yaml;
      };
    };
  };

  systemd.services = lib.attrsets.genAttrs ["grafana" "nginx"] (lib.trivial.const {
    serviceConfig.SupplementaryGroups = [config.users.groups.keys.name];
    # Use mkDefault to merge with the default After list
    unitConfig.After = lib.mkDefault ["sops-nix.service"];
  });

  users.users = lib.attrsets.genAttrs ["grafana" "nginx"] (lib.trivial.const {
    extraGroups = [config.users.groups.keys.name];
  });
}
