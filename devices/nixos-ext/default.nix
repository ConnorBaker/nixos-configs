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
    ../../modules/headless.nix
    ../../modules/impermanence.nix
    ../../modules/mimalloc.nix
    ../../modules/networking.nix
    ../../modules/sudo.nix
    ../../modules/users.nix
    ../../modules/zram.nix

    # Configure services
    ../../modules/services/openssh.nix
    ../../modules/services/tailscale.nix

    # Configure programs
    ../../modules/programs/git.nix
    ../../modules/programs/htop.nix

    # Users
    ../../users/connorbaker.nix
  ];

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadbee5";
    hostName = "nixos-ext";
  };

  system.stateVersion = "24.05";
}
