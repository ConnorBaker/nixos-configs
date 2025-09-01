{ lib, ... }:
let
  inherit (builtins) toString;
  inherit (lib.strings) concatMapStringsSep;
in
{
  options.systemd.network.networks = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
          # Configure DHCP to get dynamic addresses, but accept only those coming from the primary router on the network.
          # This avoids having a NetGear repeater blackhole all your traffic.
          dhcpV4Config.UseDNS = false;

          # Some devices have more than one interface; they won't always be plugged in.
          linkConfig.RequiredForOnline = "no";

          networkConfig = {
            DHCP = "yes";
            DNS = [
              # Cloudflare
              "1.1.1.1"
              "2606:4700:4700::1111"
              "1.0.0.1"
              "2606:4700:4700::1001"

              # Public Nat64 -- https://nat64.net
              "2a01:4f8:c2c:123f::1"
              "2a00:1098:2b::1"
            ];
            DNSOverTLS = true;
            # Hetzner doesn't support DNSSEC
            # https://docs.hetzner.com/dns-console/dns/general/dnssec/#dnssec-and-hetzner-online
            DNSSEC = "allow-downgrade";
          };

          # Larger TCP window sizes, courtesy of
          # https://wiki.archlinux.org/title/Systemd-networkd#Speeding_up_TCP_slow-start
          routes = lib.mkAfter [
            {
              Gateway = config.networkConfig.Gateway or "_dhcp4";
              InitialCongestionWindow = 50;
              InitialAdvertisedReceiveWindow = 50;
            }
          ];
        }
      )
    );
  };

  config = {
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
        "net.ipv4.tcp_rmem" = concatMapStringsSep " " toString [
          mem_min
          rmem_default
          mem_max
        ];
        "net.ipv4.udp_rmem_min" = mem_min;

        # WMEM
        "net.core.wmem_default" = wmem_default;
        "net.core.wmem_max" = mem_max;
        "net.ipv4.tcp_wmem" = concatMapStringsSep " " toString [
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

    networking = {
      useDHCP = false; # Disable the "pile of scripts" approach to networking.
      useNetworkd = true;
    };

    services = {
      bpftune.enable = true;
      resolved.enable = true;
    };

    systemd.network = {
      enable = true;
      wait-online.enable = false;
      networks = {
        "10-ether".matchConfig = {
          Kind = "!*";
          Type = [ "ether" ];
        };

        "20-wlan-station".matchConfig = {
          WLANInterfaceType = "station";
          Type = [ "wlan" ];
          SSID = "*";
        };
      };
    };
  };
}
