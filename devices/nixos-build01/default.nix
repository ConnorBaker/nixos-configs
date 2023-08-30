{
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko

    # ZFS-relevant changes to boot, networking, services, etc.
    ./zfs.nix

    # Changes for impermanence
    ./impermanence.nix

    # Configure Nix
    ../../modules/nix/nix.nix

    # Configure system
    ../../modules/boot.nix
    ../../modules/cpu-hardware.nix
    ../../modules/networking.nix
    ../../modules/headless.nix
    ../../modules/users.nix
    ../../modules/mimalloc.nix
    ../../modules/zram.nix
    ../../modules/sudo.nix

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
    "ssh/ssh_host_rsa_key.pub".source = ./keys/ssh_host_rsa_key.pub;
  };

  networking.hostName = "nixos-build01";
  system.stateVersion = "23.05";
}
