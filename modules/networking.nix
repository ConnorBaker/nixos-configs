{ config, lib, pkgs, ... }:
{
  boot.kernel.sysctl =
    let
      KB = 1024;
      MB = 1024 * KB;

      # Memory settings
      mem_min = 8 * KB;
      rmem_default = 128 * KB;
      wmem_default = 16 * KB;
      mem_max = 16 * MB;
    in
    {
      # Enable BPF JIT for better performance
      "net.core.bpf_jit_enable" = 1;
      "net.core.bpf_jit_harden" = 0;

      # Change the default queueing discipline to cake and the congestion control algorithm to BBR
      "net.core.default_qdisc" = "cake";
      "net.ipv4.tcp_congestion_control" = "bbr";

      # Largely taken from https://wiki.archlinux.org/title/sysctl and
      # https://github.com/redhat-performance/tuned/blob/master/profiles/network-throughput/tuned.conf#L10
      "net.core.somaxconn" = 8 * 1024;
      "net.core.netdev_max_backlog" = 16 * 1024;
      "net.core.optmem_max" = 64 * KB;

      # RMEM
      "net.core.rmem_default" = rmem_default;
      "net.core.rmem_max" = mem_max;
      "net.ipv4.tcp_rmem" = lib.concatMapStringsSep " " builtins.toString [
        mem_min
        rmem_default
        mem_max
      ];
      "net.ipv4.udp_rmem_min" = mem_min;

      # WMEM
      "net.core.wmem_default" = wmem_default;
      "net.core.wmem_max" = mem_max;
      "net.ipv4.tcp_wmem" = lib.concatMapStringsSep " " builtins.toString [
        mem_min
        wmem_default
        mem_max
      ];
      "net.ipv4.udp_wmem_min" = mem_min;

      # General TCP
      "net.ipv4.tcp_fastopen" = 3;
      "net.ipv4.tcp_fin_timeout" = 10;
      "net.ipv4.tcp_keepalive_intvl" = 10;
      "net.ipv4.tcp_keepalive_probes" = 6;
      "net.ipv4.tcp_keepalive_time" = 60;
      "net.ipv4.tcp_max_syn_backlog" = 8 * 1024;
      "net.ipv4.tcp_max_tw_buckets" = 2000000;
      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_slow_start_after_idle" = 0;
      "net.ipv4.tcp_tw_reuse" = 1;
    };

  # Disable the old-style Networking and use systemd
  networking.useDHCP = false;

  # TODO: Remove this once the limit on duplicate cert issuances is reset
  security.pki.certificateFiles =
    lib.warn
      ''
        USING LETSENCRYPT STAGING CERTIFICATES
        This is only for testing purposes and should not be used in production.
      ''
      [
        (pkgs.fetchurl {
          url = "https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem";
          hash = "sha256-Ol4RceX1wtQVItQ48iVgLkI2po+ynDI5mpWSGkroDnM=";
        })
        (pkgs.fetchurl {
          url = "https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x2.pem";
          hash = "sha256-SXw2wbUMDa/zCHDVkIybl68pIj1VEMXmwklX0MxQL7g=";
        })
      ];

  services = {
    bpftune.enable = true;
    resolved =
      let
        cfg = config.systemd.network.networks."10-ethernet".networkConfig;
        boolOrStringToString = bs: if lib.isString bs then bs else lib.boolToString bs;
      in
      {
        enable = true;
        fallbackDns = cfg.DNS;
        dnssec = boolOrStringToString cfg.DNSSEC;
        dnsovertls = boolOrStringToString cfg.DNSOverTLS;
      };
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks."10-ethernet" = {
      # Match on ethernet interfaces
      matchConfig.Name = "en*";

      # Configure DHCP to get dynamic addresses, but accept only those coming from the primary router on the network.
      # This avoids having a NetGear repeater blackhole all your traffic.
      # NOTE: Upstream to Nixpkgs? Missing this option.
      extraConfig = ''
        [DHCPv4]
        AllowList=192.168.1.1
      '';
      dhcpV4Config.UseDNS = false;
      networkConfig = {
        DHCP = true;
        DNS = [
          # Cloudflare
          "1.1.1.1"
          "1.0.0.1"

          # Public Nat64 -- https://nat64.net
          "2a01:4f8:c2c:123f::1"
          "2a00:1098:2b::1"
        ];
        DNSOverTLS = true;
        DNSSEC = true;
      };

      # Some devices have more than one interface; they won't always be plugged in.
      linkConfig.RequiredForOnline = "no";

      # Larger TCP window sizes, courtesy of
      # https://wiki.archlinux.org/title/Systemd-networkd#Speeding_up_TCP_slow-start
      routes = [
        {
          routeConfig = {
            Gateway = "_dhcp4";
            InitialCongestionWindow = 50;
            InitialAdvertisedReceiveWindow = 50;
          };
        }
      ];
    };
  };
}
