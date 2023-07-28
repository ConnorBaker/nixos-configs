{
  config,
  pkgs,
  ...
}: let
  grafanaDomain = config.services.grafana.settings.server.domain;
  grafanaHttpAddr = config.services.grafana.settings.server.http_addr;
  grafanaHttpPort = config.services.grafana.settings.server.http_port;
  grafanaProtocol = config.services.grafana.settings.server.protocol;
in {
  services = {
    grafana = {
      enable = true;
      provision = {
        enable = true;
        dashboards.settings.providers = [
          # TODO(@connorbaker): NVIDIA exporters.
          # Look at dcgm-exporter: https://github.com/NixOS/nixpkgs/pull/235024
          # Might be missing NixOS module.
          # https://grafana.com/grafana/dashboards/12239-nvidia-dcgm-exporter-dashboard/
          # TODO(@connorbaker): ZFS dashboards:
          # - https://grafana.com/grafana/dashboards/15008-zfs/
          # - https://grafana.com/grafana/dashboards/15362-zfs-pool-metrics/
          # - https://grafana.com/grafana/dashboards/17350-zfs-pool-metrics-influxdb-v2/
          {
            name = "Node Exporter Full";
            options.path = let
              src = pkgs.fetchFromGitHub {
                owner = "rfmoz";
                repo = "grafana-dashboards";
                rev = "73427563c80cb145f764462cd362c60f20358060";
                sha256 = "sha256-f/hDBEykQAe5Jwp8wIZV5sPauZztToO7TyhxzMP/4GY=";
              };
            in "${src}/prometheus/node-exporter-full.json";
          }
        ];
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://localhost:${toString config.services.prometheus.port}";
            jsonData = {
              cacheLevel = "High";
              incrementalQuerying = true;
              incrementalQueryOverlapWindow = "10m";
              prometheusType = "Prometheus";
              prometheusVersion = config.services.prometheus.package.version;
            };
          }
        ];
      };
      settings = {
        database = {
          type = "sqlite3";
          wal = true;
        };
        server = {
          enable_gzip = true;
          http_addr = "localhost";
          http_port = 3000;
          root_url = "${grafanaProtocol}://${grafanaDomain}/grafana";
        };
      };
    };
    nginx = {
      enable = true;
      enableReload = true;
      
      package = pkgs.nginxQuic;
      recommendedBrotliSettings = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedZstdSettings = true;

      # https://github.com/numtide/srvos/blob/ce0426c357c077edec3aacde8e9649f30f1be659/nixos/mixins/nginx.nix#L15-L17
      commonHttpConfig = "access_log syslog:server=unix:/dev/log;";

      virtualHosts.${grafanaDomain} = {
        http3 = true;
        kTLS = true;
        quic = true;
        locations."/grafana/" = {
          proxyPass = "https://${toString grafanaHttpAddr}:${toString grafanaHttpPort}/";
          proxyWebsockets = true;
        };
      };
    };
    prometheus = {
      enable = true;
      port = 9090;
      scrapeConfigs = let
        inherit (config.services.prometheus.exporters) node;
      in [
        {
          job_name = "node";
          static_configs = [{targets = ["localhost:${toString node.port}"];}];
        }
        # {
        #   job_name = "zfs";
        #   static_configs = [{targets = ["localhost:${toString zfs.port}"];}];
        # }
      ];
      exporters.node = {
        enable = true;
        enabledCollectors = [
          "buddyinfo"
          "cgroups"
          # "cpu_vulnerabilities" # TODO(@connorbaker): Not yet in NixOS.
          "ethtool"
          "interrupts"
          "ksmd"
          "processes"
          "systemd"
        ];
        port = 9100;
      };
      # zfs.enable = true;
    };
  };
}
