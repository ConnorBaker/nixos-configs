{
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko.nix

    # Secrets
    ./secrets.nix

    # Configure Nix
    ../../modules/nix

    # Configure system
    ../../modules/boot.nix
    ../../modules/docker.nix
    ../../modules/headless.nix
    ../../modules/impermanence.nix
    ../../modules/mimalloc.nix
    ../../modules/networking.nix
    ../../modules/sudo.nix
    ../../modules/users.nix
    ../../modules/zfs.nix
    ../../modules/zram.nix

    # Configure services
    ../../modules/services/openssh.nix
    ../../modules/services/prometheus-exporters.nix
    ../../modules/services/tailscale.nix

    # Users
    ../../users/connorbaker.nix
  ];

  # The ZFS module only reset rpool by default; we also want to reset dpool.
  # boot.initrd.postDeviceCommands = lib.mkAfter ''
  #   zfs rollback -r dpool@blank
  # '';

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadbee5";
    hostName = "nixos-ext";
  };

  system.stateVersion = "24.05";
}
