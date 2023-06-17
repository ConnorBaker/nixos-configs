{
  # From https://github.com/numtide/srvos/blob/01d15efe6df0d2988a65beba28d03eff0dae48d4/nixos/server/default.nix#L84-L88.
  # use TCP BBR has significantly increased throughput and reduced latency for connections
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };
  networking = {
    firewall.allowPing = true;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };
}
