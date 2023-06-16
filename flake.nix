{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.queued-build-hook.url = "github:nix-community/queued-build-hook";
  outputs = {
    self,
    nixpkgs,
    queued-build-hook,
  }: {
    nixosConfigurations.nixos-desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        queued-build-hook.nixosModules.queued-build-hook
        ./modules/nixos-desktop
      ];
    };
  };
}

