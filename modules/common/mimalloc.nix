{
  environment.memoryAllocator.provider = "mimalloc";

  nixpkgs.overlays = [
    # Must be disabled to use mimalloc
    (_: prev: {
      dhcpcd = prev.dhcpcd.override {enablePrivSep = false;};
    })
  ];
}
