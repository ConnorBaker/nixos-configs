{
  inputs = {
    attic = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:zhaofengli/attic";
    };

    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko";
    };

    flake-parts = {
      inputs.nixpkgs-lib.follows = "nixpkgs";
      url = "github:hercules-ci/flake-parts";
    };

    histodu = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:oxalica/histodu";
    };

    git-hooks-nix = {
      inputs = {
        nixpkgs-stable.follows = "";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:cachix/git-hooks.nix";
    };

    impermanence.url = "github:nix-community/impermanence";

    jetpack-nixos = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:anduril/jetpack-nixos";
    };

    nix-direnv = {
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:nix-community/nix-direnv";
    };

    nix-ld-rs = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/nix-ld-rs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpkgs.url = "github:ConnorBaker/nixpkgs/feat/nvidia-dcgm-prometheus-exporter-module";

    sops-nix = {
      inputs = {
        nixpkgs-stable.follows = "";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:Mic92/sops-nix";
    };

    treefmt-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/treefmt-nix";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      imports = [
        # Add tools to the environment for the linters etc.
        {
          perSystem =
            { system, ... }:
            {
              _module.args.pkgs =
                let
                  # Configuration for nixpkgs as a NixOS module.
                  nixpkgsModule = import ./nixpkgs-module.nix { inherit inputs system; };
                  # The actual arguments provided to instantiate nixpkgs.
                  nixpkgsArgs = nixpkgsModule.nixpkgs;
                in
                import inputs.nixpkgs nixpkgsArgs;
            };
        }
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks-nix.flakeModule
      ];

      perSystem =
        { config, pkgs, ... }:
        {
          legacyPackages = pkgs;
          pre-commit.settings.hooks = {
            # Formatter checks
            treefmt = {
              enable = true;
              package = config.treefmt.build.wrapper;
            };

            # Nix checks
            deadnix.enable = true;
            nil.enable = true;
            statix.enable = true;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              # Markdown
              mdformat.enable = true;

              # Nix
              nixfmt = {
                enable = true;
                package = pkgs.nixfmt-rfc-style;
              };

              # Shell
              shellcheck.enable = true;
              shfmt.enable = true;

              # YAML
              yamlfmt.enable = true;
            };
            # (ab)use options to pass a hidden file to be formatted.
            # See https://github.com/numtide/treefmt/issues/153.
            settings.formatter.yamlfmt.options = [ ".sops.yaml" ];
          };
        };

      flake.nixosConfigurations =
        let
          x86_64-linux-template =
            extraModules:
            inputs.nixpkgs.lib.nixosSystem {
              modules = [
                (import ./nixpkgs-module.nix {
                  inherit inputs;
                  system = "x86_64-linux";
                })
                inputs.sops-nix.nixosModules.sops
                inputs.disko.nixosModules.disko
                inputs.impermanence.nixosModules.impermanence
                inputs.attic.nixosModules.atticd
              ] ++ extraModules;
            };
        in
        {
          nixos-build01 = x86_64-linux-template [ ./devices/nixos-build01 ];
          nixos-cantcache-me = x86_64-linux-template [ ./devices/nixos-cantcache-me ];
          nixos-desktop = x86_64-linux-template [ ./devices/nixos-desktop ];
          nixos-ext = x86_64-linux-template [ ./devices/nixos-ext ];
        };
    };
}
