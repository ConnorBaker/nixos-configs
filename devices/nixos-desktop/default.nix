{
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko

    # Secrets
    ./secrets.nix

    # Configure Nix
    ../../modules/nix

    # Hercules
    ../../modules/hercules-ci-agent.nix

    # Configure system
    ../../modules/boot.nix
    ../../modules/cpu-hardware.nix
    ../../modules/docker.nix
    ../../modules/headless.nix
    ../../modules/impermanence.nix
    ../../modules/mimalloc.nix
    ../../modules/networking.nix
    ../../modules/nvidia.nix
    ../../modules/sudo.nix
    ../../modules/users.nix
    ../../modules/zfs.nix
    ../../modules/zram.nix

    # Configure services
    ../../modules/services/harmonia
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

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadabcd";
    hostName = "nixos-desktop";
  };

  system.stateVersion = "24.05";
}
