{
  imports = [
    ./hardware.nix
    ../modules/nix.nix

    ../modules/boot.nix
    ../modules/cpu-hardware.nix
    ../modules/networking.nix

    ../modules/services/openssh.nix
    ../modules/services/tailscale.nix

    ../modules/headless.nix

    ../modules/sudo.nix
    ../modules/users.nix

    ../modules/mimalloc.nix
    ../modules/zram.nix

    ../modules/nix-cantcacheme.nix
    ../modules/nix-cantcacheme-upload.nix
    ../modules/nix-cuda-maintainers.nix

    ../modules/programs/git.nix
    ../modules/programs/htop.nix
    ../modules/programs/nix-ld.nix

    ../users/connorbaker.nix
  ];
  networking.hostName = "nixos-desktop";
  system.stateVersion = "23.05";
}
