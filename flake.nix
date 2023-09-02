{
  # When we use the overlay attribute of a flake, we fetch the dependency as a flake.
  # If there's no overlay, we essentially build our own, so we just fetch the source
  # as a tarball.
  inputs = {
    alejandra = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:kamadorueda/alejandra";
    };

    deadnix = {
      inputs = {
        utils.follows = "flake-utils";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:astro/deadnix";
    };

    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko";
    };

    flake-parts = {
      inputs.nixpkgs-lib.follows = "nixpkgs";
      url = "github:hercules-ci/flake-parts";
    };

    flake-utils.url = "github:numtide/flake-utils";

    impermanence.url = "github:nix-community/impermanence";

    nil = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:oxalica/nil";
    };

    nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:NixOS/nix";
    };

    nix-ld-rs = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/nix-ld-rs";
    };

    nix-output-monitor = {
      flake = false;
      url = "github:maralorn/nix-output-monitor";
    };

    nixpkgs-review = {
      flake = false;
      url = "github:mic92/nixpkgs-review";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpkgs.url = "github:ConnorBaker/nixpkgs/feat/nvidia-dcgm-prometheus-exporter-module";

    # queued-build-hook.url = "github:nix-community/queued-build-hook";

    pre-commit-hooks-nix = {
      inputs = {
        flake-utils.follows = "flake-utils";
        nixpkgs-stable.follows = "nixpkgs";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:cachix/pre-commit-hooks.nix";
    };

    sops-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Mic92/sops-nix";
    };

    statix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nerdypepper/statix";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({withSystem, ...}: {
      systems = ["x86_64-linux"];

      imports = [
        inputs.pre-commit-hooks-nix.flakeModule
        ./nixpkgs-overlays.nix
      ];

      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
        pre-commit.settings.hooks = {
          alejandra.enable = true;
          deadnix.enable = true;
          nil.enable = true;
          statix.enable = true;
        };
      };

      flake.nixosConfigurations = {
        nixos-desktop = withSystem "x86_64-linux" ({pkgs, ...}:
          inputs.nixpkgs.lib.nixosSystem {
            inherit pkgs;
            modules = [
              inputs.sops-nix.nixosModules.sops
              ./devices/nixos-desktop
            ];
          });

        # TODO: nixos-ext and nixos-build01 can be factored out into a module for systems running ZFS with rpool.
        nixos-ext = withSystem "x86_64-linux" ({pkgs, ...}:
          inputs.nixpkgs.lib.nixosSystem {
            inherit pkgs;
            modules = [
              inputs.sops-nix.nixosModules.sops
              inputs.disko.nixosModules.disko
              inputs.impermanence.nixosModules.impermanence
              ./devices/nixos-ext
            ];
          });

        nixos-build01 = withSystem "x86_64-linux" ({pkgs, ...}:
          inputs.nixpkgs.lib.nixosSystem {
            inherit pkgs;
            modules = [
              inputs.sops-nix.nixosModules.sops
              inputs.disko.nixosModules.disko
              inputs.impermanence.nixosModules.impermanence
              ./devices/nixos-build01
            ];
          });
      };
    });
}
