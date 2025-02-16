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

    histodu = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:oxalica/histodu";
    };

    git-hooks-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
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
      inherit (lib.filesystem) packagesFromDirectoryRecursive;
      inherit (lib.strings) mesonBool versionOlder;
      inherit (lib.trivial) warnIf;

      warnIfSelectedIsOlderThanDefault =
        selected: default:
        warnIf (versionOlder selected.version default.version) ''
          The version of ${selected.pname} in use is ${selected.version}, which is older than the latest available (${default.version}).
        '' selected;

      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      mkNixpkgs =
        system:
        import inputs.nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
            cudaCapabilities = [ "8.9" ];
          };
          overlays = [
            # Misc tools
            inputs.nix-direnv.overlays.default
            (_: _: { inherit (inputs.histodu.packages.${system}) histodu; })
            # Overlay for newer version of:
            # - Nix
            # - nixpkgs-review
            # - nix-output-monitor
            # - nix-eval-jobs
            (
              final: prev:
              let
                # Includes unreleased fixes for flickering.
                nix-output-monitor' = prev.nix-output-monitor.overrideAttrs {
                  version = "2.1.4-unstable-2024-11-28";
                  src = final.fetchFromGitHub {
                    owner = "maralorn";
                    repo = "nix-output-monitor";
                    rev = "3b1ca76b0ff191728073573fa21706da0f003084";
                    hash = "sha256-fIncQSuI2AqKuVaxFR3+BIDqzpYPKxKSMKomPUWAIc0=";
                  };
                };
                # Includes fixes for Nix 2.26.
                nix-eval-jobs' = prev.nix-eval-jobs.overrideAttrs {
                  version = "2.26.0";
                  src = final.fetchFromGitHub {
                    owner = "nix-community";
                    repo = "nix-eval-jobs";
                    rev = "4b392b284877d203ae262e16af269f702df036bc";
                    hash = "sha256-3wIReAqdTALv39gkWXLMZQvHyBOc3yPkWT2ZsItxedY=";
                  };
                  buildInputs = [
                    final.boost
                    final.nix.dev.outPath # See https://github.com/nix-community/nix-eval-jobs/pull/352
                    final.curl
                    final.nlohmann_json
                  ];
                  # For some reason, builds with type "plain" and LTO disabled by default.
                  mesonBuildType = "release";
                  mesonFlags = [ (mesonBool "b_lto" true) ];
                };
              in
              {
                # By default, nix is an alias to nixVersions.stable.
                nix = final.nixVersions.latest;
                nix-output-monitor = warnIfSelectedIsOlderThanDefault nix-output-monitor' prev.nix-output-monitor;
                nix-eval-jobs = warnIfSelectedIsOlderThanDefault nix-eval-jobs' prev.nix-eval-jobs;
                nixVersions = prev.nixVersions.extend (
                  _: prevNixVersions: {
                    latest = warnIfSelectedIsOlderThanDefault prevNixVersions.nix_2_26 prevNixVersions.latest;
                  }
                );
              }
            )
            # Overlay for Caddy
            (
              final: _:
              packagesFromDirectoryRecursive {
                inherit (final) callPackage;
                directory = ./packages;
              }
            )
          ];
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
              pkgs = nixpkgsInstances.x86_64-linux;
              modules = [
                inputs.sops-nix.nixosModules.sops
                inputs.disko.nixosModules.disko
                inputs.impermanence.nixosModules.impermanence
              ] ++ extraModules;
            };
        in
        {
          nixos-build01 = x86_64-linux-template [ ./devices/nixos-build01 ];
          # nixos-cantcache-me = x86_64-linux-template [ ./devices/nixos-cantcache-me ];
          nixos-desktop = x86_64-linux-template [ ./devices/nixos-desktop ];
          nixos-ext = x86_64-linux-template [ ./devices/nixos-ext ];
        };
    };
}
