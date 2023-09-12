{
  config,
  lib,
  ...
}: {
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko

    # Secrets
    ./secrets.nix

    # Configure Nix
    ../../modules/nix/nix.nix

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
    ../../modules/services/openssh.nix
    ../../modules/services/tailscale.nix

    # Configure programs
    ../../modules/programs/git.nix
    ../../modules/programs/htop.nix

    # Users
    ../../users/connorbaker.nix
  ];

  # The ZFS module only reset rpool by default; we also want to reset dpool.
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r dpool@blank
  '';

  environment.etc = {
    "ssh/id_${config.networking.hostName}_nix_ed25519.pub".source = ./. + "/keys/id_${config.networking.hostName}_nix_ed25519.pub";
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
    "ssh/ssh_host_rsa_key.pub".source = ./keys/ssh_host_rsa_key.pub;
  };

  networking = {
    hostId = "deadbee5";
    hostName = "nixos-ext";
  };

  system.stateVersion = "23.05";
}
