{
  imports = [
    ../modules/nix
    ../modules/boot.nix
    ../modules/docker.nix
    ../modules/headless.nix
    ../modules/impermanence.nix
    ../modules/networking.nix
    ../modules/sudo.nix
    ../modules/users.nix
    ../modules/zfs.nix
    ../modules/zram.nix
    ../modules/services/openssh.nix
    ../modules/services/tailscale.nix
    ../users/connorbaker.nix
  ];
}
