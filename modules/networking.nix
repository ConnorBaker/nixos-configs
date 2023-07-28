{lib, ...}: {
  # From https://github.com/numtide/srvos/blob/01d15efe6df0d2988a65beba28d03eff0dae48d4/nixos/server/default.nix#L84-L88.
  # use TCP BBR has significantly increased throughput and reduced latency for connections
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };
  # Credits to https://github.com/numtide/srvos/blob/ce0426c357c077edec3aacde8e9649f30f1be659/nixos/common/networking.nix

  networking = {
    firewall = {
      # Allow PMTU / DHCP
      allowPing = true;
      # Keep dmesg/journalctl -k output readable by NOT logging
      # each refused connection on the open internet.
      logRefusedConnections = false;
    };
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    # Use networkd instead of the pile of shell scripts
    useNetworkd = lib.mkDefault true;
    # TODO(@connorbaker): Disabling useDHCP breaks the network and prevents access for the desktop.
    # useDHCP = lib.mkDefault false;
  };

  systemd = {
    # The notion of "online" is a broken concept
    # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
    network.wait-online.enable = false;
    services = {
      NetworkManager-wait-online.enable = false;

      # Do not take down the network for too long when upgrading,
      # This also prevents failures of services that are restarted instead of stopped.
      # It will use `systemctl restart` rather than stopping it with `systemctl stop`
      # followed by a delayed `systemctl start`.
      systemd-networkd.stopIfChanged = false;
      # Services that are only restarted might be not able to resolve when resolved is stopped
      # before
      systemd-resolved.stopIfChanged = false;
    };
  };
}
