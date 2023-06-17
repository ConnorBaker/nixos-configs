{
  config,
  lib,
  ...
}: {
  environment.memoryAllocator.provider = "mimalloc";

  nixpkgs.overlays = lib.lists.optionals config.networking.dhcpcd.enable [
    # Must be disabled to use mimalloc
    (_: prev: {
      dhcpcd = prev.dhcpcd.override {enablePrivSep = false;};
    })
  ];
}
