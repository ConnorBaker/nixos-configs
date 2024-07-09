{ config, lib, ... }:
let
  prometheusUser =
    let
      inherit (config.users.users.prometheus) name;
      expectedName = "prometheus";
    in
    assert lib.asserts.assertMsg (name == expectedName) "${expectedName} user name changed to ${name}!";
    name;
  prometheusKey = "prometheus/grafanacloud-connorbaker-prom-password";
in
{
  networking.firewall = {
    allowedTCPPorts = [ 9090 ];
    allowedUDPPorts = [ 9090 ];
  };
  sops.secrets.${prometheusKey} = {
    owner = prometheusUser;
    mode = "0440";
    path = "/etc/${prometheusKey}";
    sopsFile = ./secrets.yaml;
  };
  services.prometheus = {
    enable = true;
    enableReload = true;
    globalConfig.scrape_interval = "5s";
    port = 9090;
    remoteWrite = [
      {
        name = "grafanacloud-connorbaker-prom";
        url = "https://prometheus-prod-36-prod-us-west-0.grafana.net/api/prom/push";
        basic_auth = {
          username = "1672197";
          password_file = config.sops.secrets."prometheus/grafanacloud-connorbaker-prom-password".path;
        };
      }
    ];
    scrapeConfigs =
      let
        inherit (config.services.prometheus.exporters) node zfs;
      in
      [
        {
          job_name = "node";
          static_configs = [
            {
              targets = [ "${config.networking.hostName}:${toString node.port}" ];
              labels.instance = config.networking.hostName;
            }
          ];
        }
        {
          job_name = "zfs";
          static_configs = [
            {
              targets = [ "${config.networking.hostName}:${toString zfs.port}" ];
              labels.instance = config.networking.hostName;
            }
          ];
        }
      ];
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "buddyinfo"
          "cgroups"
          "cpu_vulnerabilities"
          "ethtool"
          "interrupts"
          "ksmd"
          "processes"
          "systemd"
        ];
        openFirewall = true;
        port = 9100;
      };
      zfs = {
        enable = true;
        openFirewall = true;
        port = 9134;
      };
    };
  };
}
