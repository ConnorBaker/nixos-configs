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
      # TODO(@connorbaker): Switch back to upstream when
      # https://github.com/nix-community/queued-build-hook/pull/22 is merged.
      url = "github:connorbaker/queued-build-hook/patch-1";
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
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
      };
      flake.nixosConfigurations.nixos-desktop = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          inputs.queued-build-hook.nixosModules.queued-build-hook
          inputs.sops-nix.nixosModules.sops
          ./nixos-desktop
        ];
      };
    };
}
