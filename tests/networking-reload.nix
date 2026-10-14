{ pkgs, networkFiles }:
let
  inherit (pkgs) lib;
  # Read the reviewed production rendering; substitute only the QEMU MACs.
  rendered = networkFiles;
  primaryMAC = "52:54:00:12:01:01";
  secondaryMAC = "52:54:00:12:02:01";
  adapt = lib.replaceStrings [ "58:11:22:b4:9d:69" "58:11:22:b4:9d:68" ] [ primaryMAC secondaryMAC ];
  staged = lib.mapAttrs' (
    name: text: lib.nameValuePair "network-after/${name}" { text = adapt text; }
  ) rendered;
  oldNetwork = ''
    [Match]
    Kind=!*
    Type=ether

    [Link]
    MACAddress=${primaryMAC}
    RequiredForOnline=no

    [Network]
    Address=192.168.1.12/24
    DHCP=ipv6
    Gateway=192.168.1.1

    [Route]
    Gateway=192.168.1.1
    GatewayOnLink=true

    [Route]
    Destination=192.168.1.1

    [Route]
    Gateway=192.168.1.1
    InitialCongestionWindow=50
    InitialAdvertisedReceiveWindow=50
  '';
  common = {
    networking = {
      useDHCP = false;
      useNetworkd = true;
      firewall.enable = false;
    };
    systemd = {
      network = {
        wait-online.enable = false;
        networks."00-ignore-eth0" = {
          matchConfig.Name = "eth0";
          linkConfig.Unmanaged = true;
        };
      };
      services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
    };
    virtualisation = {
      # Prevent test infrastructure from assigning unrelated addresses/routes.
      interfaces = {
        eth1 = {
          vlan = 1;
          assignIP = false;
        };
        eth2 = {
          vlan = 2;
          assignIP = false;
        };
      };
      memorySize = 768;
      cores = 1;
      diskSize = 2048;
      # Explicit disk-backed ext4 root; no host filesystem/network mutation.
      diskImage = "./network-reload.qcow2";
    };
    environment.systemPackages = [ pkgs.jq ];
  };

in
pkgs.testers.runNixOSTest {
  name = "fleet-networkd-live-reload";
  # Node numbering is alphabetical: client=1, router=2. NixOS test NIC MACs
  # are 52:54:00:12:<VLAN>:<node>, per pinned nixos/lib/qemu-common.nix.
  nodes.client = { lib, ... }: {
    imports = [ common ];
    virtualisation.diskImage = lib.mkForce "./client-network-reload.qcow2";
    environment.etc = staged // {
      "systemd/network/10-ether.network".text = oldNetwork;
    };
  };
  nodes.router = { lib, ... }: {
    imports = [ common ];
    virtualisation.diskImage = lib.mkForce "./router-network-reload.qcow2";
    # Provider services need their static listen addresses ready at boot.
    systemd.network = {
      wait-online.enable = lib.mkForce true;
      networks = {
        "10-primary" = {
          matchConfig.Name = "eth1";
          networkConfig = {
            Address = [
              "192.168.1.1/24"
              "fd00:1::1/64"
            ];
            IPv6AcceptRA = false;
          };
        };
        "20-backup" = {
          matchConfig.Name = "eth2";
          networkConfig = {
            Address = [
              "192.168.2.1/24"
              "fd00:2::1/64"
            ];
            IPv6AcceptRA = false;
          };
        };
      };
    };
    services = {
      radvd = {
        enable = true;
        config = ''
          interface eth1 {
            AdvSendAdvert on;
            MinRtrAdvInterval 3;
            MaxRtrAdvInterval 4;
            AdvManagedFlag on;
            prefix fd00:1::/64 { AdvOnLink on; AdvAutonomous on; };
          };
          interface eth2 {
            AdvSendAdvert on;
            MinRtrAdvInterval 3;
            MaxRtrAdvInterval 4;
            AdvManagedFlag on;
            prefix fd00:2::/64 { AdvOnLink on; AdvAutonomous on; };
          };
        '';
      };
      kea = {
        dhcp4 = {
          enable = true;
          settings = {
            interfaces-config.interfaces = [ "eth2" ];
            valid-lifetime = 3600;
            lease-database = {
              type = "memfile";
              persist = false;
            };
            subnet4 = [
              {
                id = 2;
                subnet = "192.168.2.0/24";
                interface = "eth2";
                pools = [ { pool = "192.168.2.100 - 192.168.2.150"; } ];
                option-data = [
                  {
                    name = "routers";
                    data = "192.168.2.1";
                  }
                ];
              }
            ];
          };
        };
        dhcp6 = {
          enable = true;
          settings = {
            interfaces-config.interfaces = [
              "eth1"
              "eth2"
            ];
            valid-lifetime = 3600;
            preferred-lifetime = 3000;
            renew-timer = 900;
            rebind-timer = 1800;
            lease-database = {
              type = "memfile";
              persist = false;
            };
            subnet6 = [
              {
                id = 1;
                subnet = "fd00:1::/64";
                interface = "eth1";
                pools = [ { pool = "fd00:1::100 - fd00:1::1ff"; } ];
              }
              {
                id = 2;
                subnet = "fd00:2::/64";
                interface = "eth2";
                pools = [ { pool = "fd00:2::100 - fd00:2::1ff"; } ];
              }
            ];
          };
        };
      };
    };
  };
  testScript = ''
    import json
    import re

    start_all()
    # Same situation as production: primary carries traffic; secondary is
    # disconnected but was given the primary's MAC by the old broad rule.
    client.send_monitor_command("set_link virtio-net-pci.2 off")
    router.wait_for_unit("systemd-networkd.service")
    router.wait_for_unit("radvd.service")
    router.wait_for_unit("kea-dhcp4-server.service")
    router.wait_for_unit("kea-dhcp6-server.service")
    client.wait_for_unit("systemd-networkd.service")
    client.succeed('test "$(findmnt -n -o FSTYPE /)" = ext4')
    client.wait_until_succeeds("ping -c 1 -W 1 192.168.1.1")
    client.wait_until_succeeds("ping -6 -c 1 -W 1 fd00:1::1")
    client.wait_until_succeeds(
        "ip -j -6 addr show dev eth1 | jq -e '.[0].addr_info | "
        "any(.local | startswith(\"fd00:1::1\"))'"
    )
    client.wait_until_succeeds(
        "test $(ip -4 route show default dev eth1 | wc -l) -eq 3"
    )
    client.wait_until_succeeds(
        "test $(cat /sys/class/net/eth2/address) = ${primaryMAC}"
    )

    def primary_globals():
        addresses = json.loads(client.succeed("ip -j -6 addr show dev eth1"))[0]["addr_info"]
        return {a["local"] for a in addresses if a["scope"] == "global"}

    before_v6 = primary_globals()
    assert any(a.startswith("fd00:1::1") for a in before_v6), before_v6
    assert any(a.startswith("fd00:1::5054:") for a in before_v6), before_v6
    before_pid = client.succeed("systemctl show systemd-networkd -p MainPID --value").strip()
    before_mac = client.succeed("cat /sys/class/net/eth1/address").strip()
    router.succeed("ping -c 1 -W 1 192.168.1.12")
    # A newly leased address is initially tentative while DAD completes.
    # Establish usable IPv6 connections before testing reload continuity.
    for address in before_v6:
        router.wait_until_succeeds(f"ping -6 -c 1 -W 1 {address}")
    client.succeed("ip monitor address dev eth1 > /tmp/address-events.log 2>&1 </dev/null &")
    router.succeed(
        "ping -c 200 -i 0.05 -W 1 192.168.1.12 > /tmp/continuous-ping.log 2>&1 "
        "</dev/null & echo $! > /tmp/continuous-ping.pid"
    )

    # Replace the symlinked generated files with copies INSIDE THE TEST VM,
    # using the reviewed actual post-change rendering. Do not restart networkd.
    client.succeed("cp --remove-destination /etc/network-after/*.network /etc/systemd/network/")
    client.succeed("networkctl reload")
    client.wait_until_succeeds(
        "test $(ip -4 route show default dev eth1 | wc -l) -eq 1"
    )
    client.wait_until_succeeds(
        "test $(cat /sys/class/net/eth2/address) = ${secondaryMAC}"
    )
    assert client.succeed("systemctl show systemd-networkd -p MainPID --value").strip() == before_pid
    assert client.succeed("cat /sys/class/net/eth1/address").strip() == before_mac == "${primaryMAC}"
    client.succeed("ip -4 address show dev eth1 | grep -F '192.168.1.12/24'")
    assert before_v6 <= primary_globals(), (before_v6, primary_globals())
    client.succeed("ping -c 1 -W 1 192.168.1.1")
    client.succeed("ping -6 -c 1 -W 1 fd00:1::1")
    router.succeed("ping -c 1 -W 1 192.168.1.12")
    for address in before_v6:
        router.succeed(f"ping -6 -c 1 -W 1 {address}")
    # Netlink observation verifies retention, beyond merely re-adding an IP.
    events = client.succeed("cat /tmp/address-events.log")
    assert "Deleted" not in events, events
    client.fail("ip -4 route show default dev eth1 | grep -E 'onlink|initcwnd|initrwnd'")
    client.fail("ip -4 route show 192.168.1.1/32 | grep .")

    # Connect the restored secondary and verify DHCP/RA backups stay below
    # the primary in priority and never inherit the primary static address.
    client.send_monitor_command("set_link virtio-net-pci.2 on")
    client.wait_until_succeeds("ip -4 address show dev eth2 | grep '192.168.2.'")
    client.wait_until_succeeds("ip -4 route show default dev eth2 | grep 'metric 4096'")
    client.wait_until_succeeds("ip -6 route show default dev eth2 | grep 'metric 4096'")
    client.fail("ip -4 address show dev eth2 | grep -F '192.168.1.12'")
    client.succeed("ip -4 route get 203.0.113.1 | grep -F 'via 192.168.1.1 dev eth1'")
    client.succeed("ip -6 route get fd00:3::1 | grep -F 'dev eth1'")
    client.succeed("ping -c 1 -W 1 192.168.1.1")
    client.succeed("ping -6 -c 1 -W 1 fd00:1::1")
    assert before_v6 <= primary_globals()
    assert client.succeed("systemctl show systemd-networkd -p MainPID --value").strip() == before_pid

    router.wait_until_succeeds("grep -q '200 packets transmitted' /tmp/continuous-ping.log")
    ping_output = router.succeed("cat /tmp/continuous-ping.log")
    assert re.search(r"\b0% packet loss", ping_output), ping_output
    client.succeed("journalctl -u systemd-networkd --no-pager")
    router.succeed("journalctl -u kea-dhcp6-server --no-pager")
  '';
}
