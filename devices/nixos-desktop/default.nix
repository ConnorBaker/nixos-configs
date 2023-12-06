{pkgs, ...}:
{
  imports = [
    ./hardware.nix

    # Secrets
    ./secrets.nix

    # Configure Nix
    ../../modules/nix

    # Hercules
    # ../../modules/hercules-ci-agent.nix

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

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadabcd";
    hostName = "nixos-desktop";
  };

  system.stateVersion = "23.05";
}
