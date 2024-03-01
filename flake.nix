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

    flake-utils.url = "github:numtide/flake-utils";

    hercules-ci-agent = {
      inputs = {
        flake-parts.follows = "flake-parts";
        # Nix isn't explicitly stated but conditionally checked.
        # https://github.com/hercules-ci/hercules-ci-agent/blob/d3bec2bf1f042e033b4893fbc59bab141060f3c0/flake.nix#L232
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:hercules-ci/hercules-ci-agent/d3bec2bf1f042e033b4893fbc59bab141060f3c0";
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

    pre-commit-hooks-nix = {
      inputs = {
        flake-utils.follows = "flake-utils";
        nixpkgs-stable.follows = "nixpkgs";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:cachix/pre-commit-hooks.nix";
    };

    sops-nix = {
      inputs = {
        nixpkgs-stable.follows = "nixpkgs";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:Mic92/sops-nix";
    };

    treefmt-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/treefmt-nix";
    };
  };

  # For nixfmt, a Haskell application which requires IFD.
  nixConfig.allow-import-from-derivation = true;

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { withSystem, ... }:
      {
        systems = [
          "aarch64-linux"
          "x86_64-linux"
        ];

        imports = [
          # Add tools to the environment for the linters etc.
          {
            perSystem =
              {
                inputs',
                lib,
                system,
                ...
              }:
              {
                _module.args.pkgs =
                  import inputs.nixpkgs
                    (import ./nixpkgs-overlays.nix { inherit inputs inputs'; } { inherit lib system; }).nixpkgs;
              };
          }
          inputs.treefmt-nix.flakeModule
          inputs.pre-commit-hooks-nix.flakeModule
        ];

        perSystem =
          { config, pkgs, ... }:
          {
            pre-commit.settings = {
              hooks = {
                # Formatter checks
                treefmt.enable = true;

                # Nix checks
                deadnix.enable = true;
                nil.enable = true;
                statix.enable = true;
              };
              # Formatter
              settings.treefmt.package = config.treefmt.build.wrapper;
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
              withSystem "x86_64-linux" (
                { inputs', ... }:
                inputs.nixpkgs.lib.nixosSystem {
                  modules = [ (import ./nixpkgs-overlays.nix { inherit inputs inputs'; }) ] ++ extraModules;
                }
              );
          in
          {
            nixos-desktop = x86_64-linux-template [ ./devices/nixos-desktop ];
            nixos-ext = x86_64-linux-template [ ./devices/nixos-ext ];
            nixos-build01 = x86_64-linux-template [ ./devices/nixos-build01 ];
          };
      }
    );
}
