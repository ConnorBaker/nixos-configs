{
  # NOTE: Scraping is done by a separate server, not running NixOS.
  services.prometheus = {
    enable = true;
    enableReload = true;
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
