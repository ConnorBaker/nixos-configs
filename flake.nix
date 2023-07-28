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

    nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:NixOS/nix";
    };

    nix-ld-rs = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/nix-ld-rs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    queued-build-hook.url = "github:nix-community/queued-build-hook";

    sops-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
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
              {programs.nix-ld.package = inputs'.nix-ld-rs.packages.nix-ld-rs;}
              {nix.package = inputs'.nix.packages.nix;}
              ./devices/nixos-desktop
            ];
          });

        hetzner-ext = withSystem "x86_64-linux" ({inputs', ...}:
          inputs.nixpkgs.lib.nixosSystem {
            modules = [
              inputs.disko.nixosModules.disko
              inputs.sops-nix.nixosModules.sops
              {programs.nix-ld.package = inputs'.nix-ld-rs.packages.nix-ld-rs;}
              {nix.package = inputs'.nix.packages.nix;}
              ./devices/hetzner-ext
            ];
          });
      };
    });
}
