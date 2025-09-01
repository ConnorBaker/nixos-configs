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
    # ../../modules/networking.nix # TODO(@connorbaker): Try to re-enable this
    ../../modules/sudo.nix
    ../../modules/users.nix
    ../../modules/zfs.nix
    ../../modules/zram.nix

    # Configure services
    ../../modules/services/openssh.nix
    ../../modules/services/tailscale.nix

    # Users
    ../../users/connorbaker.nix
  ];

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadba6e";
    hostName = "nixos-azure01";
  };

  # TODO(@connorbaker): From networking.
  services.bpftune.enable = true;

  system.stateVersion = "25.05";
}
