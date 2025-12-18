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

    git-hooks-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:cachix/git-hooks.nix";
    };

    histodu = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:oxalica/histodu";
    };

    impermanence.url = "github:nix-community/impermanence";

    jetpack-nixos = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:anduril/jetpack-nixos";
    };

    nil = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:oxalica/nil";
    };

    nix-direnv = {
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:nix-community/nix-direnv";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Mic92/sops-nix";
    };

    treefmt-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/treefmt-nix";
    };
  };

  outputs =
    inputs:
    let
      inherit (inputs.flake-parts.lib) mkFlake;
      inherit (inputs.nixpkgs) lib;
      inherit (lib.attrsets) genAttrs;
      inherit (lib.strings) mesonBool;

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      overlays = [
        # Misc tools
        inputs.nix-direnv.overlays.default
        (final: _: { inherit (inputs.histodu.packages.${final.system}) histodu; })
        inputs.nil.overlays.default
        (final: prev: {
          nixVersions = prev.nixVersions.extend (finalNixVersions: _: { stable = finalNixVersions.latest; });
        })
      ];

      config.allowUnfree = true;

      mkNixpkgs =
        system:
        import inputs.nixpkgs {
          inherit config overlays system;
        };

      # Memoization through lambda lifting.
      nixpkgsInstances = genAttrs systems mkNixpkgs;
    in
    mkFlake { inherit inputs; } {
      inherit systems;

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks-nix.flakeModule
      ];

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        {
          _module.args.pkgs = nixpkgsInstances.${system};

          legacyPackages = pkgs;

          # packages = lib.mkIf (system == "x86_64-linux") {
          #   orin-flash-script =
          #     (inputs.self.nixosConfigurations.nixos-orin.extendModules {
          #       modules = [ { nixpkgs.buildPlatform = { inherit system; }; } ];
          #     }).config.system.build.flashScript;
          # };

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
          mkSystem =
            extraModules:
            inputs.nixpkgs.lib.nixosSystem {
              modules = [
                inputs.sops-nix.nixosModules.sops
                inputs.disko.nixosModules.disko
                inputs.impermanence.nixosModules.impermanence
                {
                  nixpkgs = { inherit config overlays; };
                }
              ]
              ++ extraModules;
            };
        in
        {
          nixos-build01 = mkSystem [
            { nixpkgs.hostPlatform.system = "x86_64-linux"; }
            ./devices/nixos-build01
          ];

          nixos-desktop = mkSystem [
            {
              nixpkgs = {
                config = {
                  # Globally set cudaSupport changes hwloc which causes Nix rebuilds
                  # cudaSupport = true;
                  cudaCapabilities = [ "8.9" ];
                };
                hostPlatform.system = "x86_64-linux";
              };
            }
            ./devices/nixos-desktop
          ];

          nixos-ext = mkSystem [
            { nixpkgs.hostPlatform.system = "x86_64-linux"; }
            ./devices/nixos-ext
          ];

          nixos-orin = mkSystem [
            {
              nixpkgs.config = {
                cudaSupport = true;
                cudaCapabilities = [ "8.7" ];
              };
            }
            inputs.jetpack-nixos.nixosModules.default
            ./devices/nixos-orin
          ];
        };
    };
}
