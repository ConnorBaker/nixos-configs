{pkgs, ...}: {
  imports = [
    ./hardware.nix

    # Configure Nix
    ../../modules/nix/nix.nix
    ./nix.nix
    # ../../modules/nix/cantcacheme/pull.nix
    # ../../modules/nix/cantcacheme/push.nix

    # Configure system
    ../../modules/boot.nix
    ../../modules/cpu-hardware.nix
    ../../modules/networking.nix
    ../../modules/headless.nix
    ../../modules/cuda.nix
    ../../modules/nvidia.nix
    ../../modules/users.nix
    ../../modules/mimalloc.nix
    ../../modules/zram.nix
    ../../modules/sudo.nix

    # Configure services
    ../../modules/services/openssh.nix
    ../../modules/services/tailscale.nix
    # ../../modules/services/monitoring.nix
    # ./monitoring.nix

    # Configure programs
    ../../modules/programs/git.nix
    ../../modules/programs/htop.nix
    ../../modules/programs/nix-ld.nix

    # Users
    ../../users/connorbaker.nix
    ./packages.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;
  networking.hostName = "nixos-desktop";
  sops.age.sshKeyPaths = ["/home/connorbaker/.ssh/id_ed25519"];
  system.stateVersion = "23.05";
}
