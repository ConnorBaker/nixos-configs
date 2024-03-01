{ config, lib, ... }:
{
  environment.memoryAllocator.provider = "mimalloc";

  nixpkgs.overlays = lib.lists.optionals config.networking.dhcpcd.enable [
    # Must be disabled to use mimalloc
    # https://github.com/NixOS/nixpkgs/blob/244ee5631a7a39b0c6bd989cdf9a1326cd3c5819/nixos/modules/services/networking/dhcpcd.nix#L212-L224
    (_: prev: { dhcpcd = prev.dhcpcd.override { enablePrivSep = false; }; })
  ];
}
