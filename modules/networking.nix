{ config, lib, ... }:
let
  inventory = import ../inventory.nix;
  host = inventory.hosts.${config.networking.hostName} or { };
  hasStaticLAN = host ? lan;

  # Uplink policy belongs only to physical links, not every .network entry.
  # In particular, Tailscale and Orin's downstream USB DHCP server own theirs.
  physicalUplink = {
    dhcpV4Config.UseDNS = false;
    linkConfig.RequiredForOnline = "no";
    networkConfig = {
      DHCP = lib.mkDefault "yes";
      DNS = [
        "1.1.1.1"
        "2606:4700:4700::1111"
        "1.0.0.1"
        "2606:4700:4700::1001"
        "2a01:4f8:c2c:123f::1"
        "2a00:1098:2b::1"
      ];
      DNSOverTLS = lib.mkDefault true;
      DNSSEC = "allow-downgrade";
    };
  };
  ethernetMatch = {
    Kind = "!*";
    Type = [ "ether" ];
  };
  # Below every primary RA preference, including a low-preference router's
  # metric 2048. DHCP backups likewise must not replace the static LAN route.
  backupUplink = lib.recursiveUpdate physicalUplink {
    dhcpV4Config.RouteMetric = 4096;
    ipv6AcceptRAConfig.RouteMetric = 4096;
  };
in
{
  boot.kernel.sysctl = {
    "net.core.bpf_jit_enable" = 1;
    "net.core.bpf_jit_harden" = 0;
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";

    # bpftune owns TCP maxima, receive buffers and network/SYN backlogs.
    # These socket/transport policies are independent of its adaptive tuning.
    "net.core.wmem_max" = 16 * 1024 * 1024;
    "net.ipv4.udp_rmem_min" = 8 * 1024;
    "net.ipv4.udp_wmem_min" = 8 * 1024;
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_keepalive_intvl" = 10;
    "net.ipv4.tcp_keepalive_probes" = 6;
    "net.ipv4.tcp_keepalive_time" = 60;
    "net.ipv4.tcp_mtu_probing" = 1;
  };

  networking = {
    useDHCP = false;
    useNetworkd = true;
  };
  services = {
    bpftune.enable = true;
    resolved.enable = true;
  };

  systemd.network = {
    wait-online.enable = false;
    networks = {
      # Preserve the current primary filename and its IP/DHCPv6/RA behavior.
      # Matching the factory MAC selects one NIC without modifying its address.
      "10-ether" = lib.recursiveUpdate physicalUplink {
        matchConfig =
          ethernetMatch
          // lib.optionalAttrs hasStaticLAN {
            PermanentMACAddress = host.lan.primaryMAC;
          };
        networkConfig = lib.optionalAttrs hasStaticLAN {
          Address = "${host.lan.ipv4}/24";
          Gateway = inventory.gateway;
          DHCP = "ipv6";
        };
      };

      "20-wlan-station" = lib.recursiveUpdate (if hasStaticLAN then backupUplink else physicalUplink) {
        matchConfig = {
          WLANInterfaceType = "station";
          Type = [ "wlan" ];
          SSID = "*";
        };
      };
    }
    // lib.optionalAttrs hasStaticLAN {
      "15-ether" = backupUplink // {
        matchConfig = ethernetMatch;
      };
    }
    // lib.optionalAttrs (hasStaticLAN && host.lan ? secondaryMAC) {
      # The previous broad rule spoofed this disconnected NIC to the primary
      # MAC. Explicitly restore its factory MAC on reload as well as at boot.
      "11-secondary-ether" = lib.recursiveUpdate backupUplink {
        matchConfig = ethernetMatch // {
          PermanentMACAddress = host.lan.secondaryMAC;
        };
        linkConfig.MACAddress = host.lan.secondaryMAC;
      };
    };
  };
}
