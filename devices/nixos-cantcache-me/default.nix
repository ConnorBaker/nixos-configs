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
    ../../modules/cpu-hardware.nix
    ../../modules/headless.nix
    ../../modules/impermanence.nix
    ../../modules/mimalloc.nix
    ../../modules/networking.nix
    ../../modules/sudo.nix
    ../../modules/users.nix
    ../../modules/zfs.nix
    ../../modules/zram.nix

    # Configure services
    ../../modules/services/binary-cache
    ../../modules/services/openssh.nix
    ../../modules/services/prometheus-exporters.nix
    ../../modules/services/tailscale.nix

    # Users
    ../../users/connorbaker.nix
  ];

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadb055";
    hostName = "nixos-cantcache-me";
  };

  system = {
    stateVersion = "24.05";
    switch = {
      enable = false;
      enableNg = true;
    };
  };
}
