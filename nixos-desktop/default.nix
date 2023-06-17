{
  imports = [
    ./hardware.nix

    # Configure Nix
    ../modules/nix/nix.nix
    ../modules/nix/cuda.nix
    ../modules/nix/cantcacheme.nix
    ../modules/nix/cantcacheme-upload.nix

    # Configure system
    ../modules/boot.nix
    ../modules/cpu-hardware.nix
    ../modules/networking.nix
    ../modules/headless.nix
    ../modules/users.nix
    ../modules/mimalloc.nix
    ../modules/zram.nix
    ../modules/sudo.nix

    # Configure services
    ../modules/services/openssh.nix
    ../modules/services/tailscale.nix

    # Configure programs
    ../modules/programs/git.nix
    ../modules/programs/htop.nix
    ../modules/programs/nix-ld.nix

    # Users
    ../users/connorbaker.nix
  ];
  networking.hostName = "nixos-desktop";
  system.stateVersion = "23.05";
}
