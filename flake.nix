{
  # When we use the overlay attribute of a flake, we fetch the dependency as a flake.
  # If there's no overlay, we essentially build our own, so we just fetch the source
  # as a tarball.
  inputs = {
    alejandra = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:kamadorueda/alejandra";
    };

    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko";
    };

    flake-parts = {
      inputs.nixpkgs-lib.follows = "nixpkgs";
      url = "github:hercules-ci/flake-parts";
    };

    impermanence.url = "github:nix-community/impermanence";

    nil = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:oxalica/nil";
    };

    nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      # url = "github:NixOS/nix/2.17.0";
      url = "github:NixOS/nix/736b9cede73692a1cf92a6c21c5259498a04c961";
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

    sops-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Mic92/sops-nix";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({withSystem, ...}: {
      systems = ["x86_64-linux"];

      imports = [
        ./nixpkgs-overlays.nix
      ];

      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
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
