{lib, ...}: {
  nixos-desktop = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [../modules/nixos-desktop];
  };
}
