{
  inputs = {
    flake-parts = {
      inputs.nixpkgs-lib.follows = "nixpkgs";
      url = "github:hercules-ci/flake-parts";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    queued-build-hook = {
      inputs = {
        devshell.follows = "";
        nixpkgs.follows = "";
        treefmt-nix.follows = "";
      };
      url = "github:nix-community/queued-build-hook";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
      };
      flake.nixosConfigurations.nixos-desktop = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          inputs.queued-build-hook.nixosModules.queued-build-hook
          ./nixos-desktop
        ];
      };
    };
}
