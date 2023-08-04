{
  inputs = {
    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko";
    };

    flake-parts = {
      inputs.nixpkgs-lib.follows = "nixpkgs";
      url = "github:hercules-ci/flake-parts";
    };

    nil = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:oxalica/nil/2023-05-09";
    };

    nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:NixOS/nix/2.15.1";
    };

    nix-ld-rs = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/nix-ld-rs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/release-23.05";
    # nixpkgs.url = "github:ConnorBaker/nixpkgs/feat/nvidia-dcgm-prometheus-exporter-module";

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
      flake.nixosConfigurations = {
        nixos-desktop = withSystem "x86_64-linux" ({inputs', ...}:
          inputs.nixpkgs.lib.nixosSystem {
            modules = [
              inputs.queued-build-hook.nixosModules.queued-build-hook
              inputs.sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  (_: _: {inherit (inputs'.nix.packages) nix;})
                  (_: _: {inherit (inputs'.nil.packages) nil;})
                  (_: _: {inherit (inputs'.nix-ld-rs.packages) nix-ld-rs;})
                ];
              }
              ./devices/nixos-desktop
            ];
          });

        nixos-ext = withSystem "x86_64-linux" ({inputs', ...}:
          inputs.nixpkgs.lib.nixosSystem {
            modules = [
              inputs.disko.nixosModules.disko
              inputs.sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  (_: _: {inherit (inputs'.nix.packages) nix;})
                ];
              }
              ./devices/nixos-ext
            ];
          });

        hetzner-ext = withSystem "x86_64-linux" ({inputs', ...}:
          inputs.nixpkgs.lib.nixosSystem {
            modules = [
              inputs.disko.nixosModules.disko
              ./devices/hetzner-ext
            ];
          });
      };
    });
}
