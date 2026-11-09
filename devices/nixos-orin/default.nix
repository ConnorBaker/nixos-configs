{
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko.nix

    # Secrets
    ./secrets.nix

    ../../profiles/builder.nix
  ];

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadba55";
    hostName = "nixos-orin";
  };

  # The Tribuchet agents' slice (modules/services/tribuchet-agent-memory.nix)
  # swaps through zswap only with memory.zswap.max and
  # memory.zswap.writeback, which this 5.15 kernel lacks (Linux 5.19 and
  # 6.8). Without them the slice's pages could go on to zram. So no swap
  # for the slice here: its cap is MemTotal less the reserve.
  services.tribuchet-worker.agentSwapPercent = 0;

  # Need to add our user to the i2c and video groups to access the GPU.
  users.users.connorbaker.extraGroups = [
    "i2c"
    "video"
  ];

  system.stateVersion = "25.05";
}
