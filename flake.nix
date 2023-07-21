{
  inputs = {
    flake-parts = {
      inputs.nixpkgs-lib.follows = "nixpkgs";
      url = "github:hercules-ci/flake-parts";
    };

    nix-ld-rs = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/nix-ld-rs";
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

    sops-nix = {
      inputs = {
        nixpkgs-stable.follows = "";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:Mic92/sops-nix";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({withSystem, ...}: {
      systems = ["x86_64-linux"];
      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
      };
      flake.nixosConfigurations.nixos-desktop = withSystem "x86_64-linux" ({inputs', ...}: let
        inherit (inputs.nixpkgs.lib) nixosSystem;
        inherit (inputs.queued-build-hook.nixosModules) queued-build-hook;
        inherit (inputs.sops-nix.nixosModules) sops;
        nix-ld-rs.programs.nix-ld.package = inputs'.nix-ld-rs.packages.nix-ld-rs;
      in
        nixosSystem {
          modules = [
            queued-build-hook
            sops
            nix-ld-rs
            ./nixos-desktop
          ];
        });
    });
}
