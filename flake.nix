{
  inputs = {
    determinate = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:determinateSystems/determinate";
    };

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
      inherit (lib.strings) mesonBool versionOlder;
      inherit (lib.trivial) warnIf;

      warnIfSelectedIsOlderThanDefault =
        selected: default:
        warnIf (versionOlder selected.version default.version) ''
          The version of ${selected.pname} in use is ${selected.version}, which is older than the latest available (${default.version}).
        '' selected;

      systems = [
        "aarch64-darwin"
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
            # - nil
            # - Nix
            # - nixpkgs-review
            # - nix-eval-jobs
            inputs.nil.overlays.default
            inputs.determinate.inputs.nix.overlays.default # changes only the top-level Nix
            (
              final: prev:
              let
                nix-eval-jobs' = prev.nix-eval-jobs.overrideAttrs {
                  # For some reason, builds with type "plain" and LTO disabled by default.
                  mesonBuildType = "release";
                  mesonFlags = [ (mesonBool "b_lto" true) ];
                };
              in
              {
                # By default, nix is an alias to nixVersions.stable, but the overlay makes this the newest version.
                # nix = final.nixVersions.latest;
                nix-eval-jobs = warnIfSelectedIsOlderThanDefault nix-eval-jobs' prev.nix-eval-jobs;
                nixVersions = prev.nixVersions.extend (
                  _: prevNixVersions: {
                    latest = warnIfSelectedIsOlderThanDefault final.nix prevNixVersions.nix_2_26;
                  }
                );
                # Patch Nil to handle duplicates in builtins attrNames in determinate nix.
                # Since the output of attrNames is sorted, we can use `dedup` since the duplicates are contiguous.
                nil = prev.nil.overrideAttrs (prevAttrs: {
                  postPatch =
                    prevAttrs.postPatch or ""
                    + ''
                      substituteInPlace crates/builtin/build.rs \
                        --replace-fail \
                          'let builtins_attr_names: Vec<String>' \
                          'let mut builtins_attr_names: Vec<String>' \
                        --replace-fail \
                          '.expect("Failed to get builtins. Is `nix` accessible?");' \
                          '.expect("Failed to get builtins. Is `nix` accessible?"); builtins_attr_names.dedup();'
                    '';
                });
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
                inputs.determinate.nixosModules.default
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
