{
  config,
  lib,
  pkgs,
  ...
}:
let
  grafanaDomain = config.services.grafana.settings.server.domain;
  grafanaCert = "./certs/${grafanaDomain}.crt";
  tailscaleKey = "tailscale/${grafanaDomain}.key";
in
{
  networking.firewall.allowedTCPPorts = [ 443 ];

  services = {
    dcgm = {
      enable = true;
      logLevel = "DEBUG";
    };

    grafana = {
      provision.dashboards.settings.providers = [
        {
          name = "NVIDIA DCGM";
          options.path = "${pkgs.prometheus-dcgm-exporter}/share/grafana/dcgm-exporter-dashboard.json";
        }
      ];
      settings = {
        server = {
          enforce_domain = true;
          domain = "nixos-desktop.rove-hexatonic.ts.net";
          cert_file = grafanaCert;
          cert_key = config.sops.secrets.${tailscaleKey}.path;
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
    };

    nginx.virtualHosts.${grafanaDomain} = {
      forceSSL = true;
      sslCertificate = grafanaCert;
      sslCertificateKey = config.sops.secrets.${tailscaleKey}.path;
    };

    prometheus = {
      globalConfig = {
        evaluation_interval = "30s";
        scrape_interval = "30s";
        scrape_timeout = "10s";
      };
      exporters = {
        # dcgm = {
        #   enable = true;
        #   port = 9400;
        # };
        node.disabledCollectors = [
          "btrfs"
          "xfs"
        ];
      };
      scrapeConfigs = [
        # {
        #   job_name = "dcgm";
        #   static_configs = [
        #     {
        #       targets = ["localhost:${toString config.services.prometheus.exporters.dcgm.port}"];
        #     }
        #   ];
        # }
      ];
    };
  };

  sops = {
    age.sshKeyPaths = [ "/home/connorbaker/.ssh/id_ed25519" ];
    secrets = {
      "grafana/admin_password" = {
        inherit (config.users.users.grafana) group;
        owner = config.users.users.grafana.name;
        restartUnits = [ "grafana.service" ];
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

  systemd.services =
    (lib.attrsets.genAttrs
      [
        "grafana"
        "nginx"
      ]
      (
        lib.trivial.const {
          serviceConfig.SupplementaryGroups = [ config.users.groups.keys.name ];
          # Use mkDefault to merge with the default After list
          unitConfig.After = lib.mkDefault [ "sops-nix.service" ];
        }
      )
    )
    // {
      # dcgm.environment.LD_LIBRARY_PATH = let
      #   libnvidia_nscq = pkgs.fetchzip {
      #     url = "https://developer.download.nvidia.com/compute/nvidia-driver/redist/libnvidia_nscq/linux-x86_64/libnvidia_nscq-linux-x86_64-535.54.03-archive.tar.xz";
      #     hash = "sha256-XcqQzJ7qGd2U4gycTuQ9qGVZKGf1xW4Q+xdf1w57mHk=";
      #   };
      # in
      #   lib.mkForce (lib.concatStringsSep ":" [
      #     "${config.hardware.nvidia.package}/lib"
      #     "${libnvidia_nscq}/lib"
      #   ]);
      # prometheus-dcgm-exporter = {
      #   environment.CUDA_HOME = "${pkgs.cudaPackages_12_2.cudatoolkit}";
      #   path = [pkgs.dcgm];
      #   serviceConfig.ExecStart = lib.mkForce ''
      #     ${lib.getExe pkgs.prometheus-dcgm-exporter} \
      #       --collectors ${config.services.prometheus.exporters.dcgm.collectors}
      #   '';
      # };
      # --address ${cfg.address}:${toString cfg.port} \
      # --collect-interval ${toString cfg.collectInterval} \
      # --kubernetes ${lib.boolToString cfg.kubernetes} \
      # --use-old-namespace ${lib.boolToString cfg.useOldNamespace} \
      # --configmap-data ${cfg.configmapData} \
      # --remote-hostengine-info ${cfg.remoteHostengineInfo} \
      # --kubernetes-gpu-id-type ${cfg.kubernetesGpuIdType} \
      # --devices ${cfg.devices} \
      # --no-hostname ${lib.boolToString cfg.noHostname} \
      # --switch-devices ${cfg.switchDevices} \
      # --fake-gpus ${lib.boolToString cfg.fakeGpus}
    };

  users.users =
    lib.attrsets.genAttrs
      [
        "grafana"
        "nginx"
      ]
      (lib.trivial.const { extraGroups = [ config.users.groups.keys.name ]; });
}
