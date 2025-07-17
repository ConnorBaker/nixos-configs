{
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko

    # Secrets
    ./secrets.nix

    # Configure Nix
    ../../modules/nix

    # Configure system
    ../../modules/boot.nix
    # ../../modules/cpu-hardware.nix # ARM hardware
    ../../modules/headless.nix
    ../../modules/impermanence.nix
    # Boehm GC, a dependency of mimalloc, doesn't pass test cases when run inside qemu
    # ../../modules/mimalloc.nix
    ../../modules/networking.nix
    ../../modules/sudo.nix
    ../../modules/users.nix
    ../../modules/zfs.nix
    ../../modules/zram.nix

    # Configure services
    ../../modules/services/openssh.nix
    ../../modules/services/tailscale.nix

    # Users
    ../../users/connorbaker.nix
    ./packages.nix
  ];

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadba55";
    hostName = "nixos-orin";
  };

  system.stateVersion = "25.05";
}
