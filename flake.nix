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

    # Upstream directly: the ConnorBaker fork carries no commits of its own
    # and had fallen behind (bzip2_1_1 removal, cuda-legacy manifests).
    jetpack-nixos = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:anduril/jetpack-nixos";
    };

    nil = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:oxalica/nil";
    };

    # Upstream master plus the PRs and patches we run; see its merge history.
    # nix-optimization applies no patches of its own on top.
    nix.url = "github:ConnorBaker/nix/integration";

    nix-optimization = {
      inputs.nix.follows = "nix";
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:ConnorBaker/nix-optimization/nixos-nix-tarmac";
    };

    nix-grpc-store = {
      inputs.nixpkgs.follows = "nixpkgs";
      # Upstream main plus the PRs and patches we run; see its merge history.
      url = "github:ConnorBaker/nix-grpc-store/integration";
    };

    nix-eval-jobs = {
      flake = false;
      url = "github:NixOS/nix-eval-jobs";
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

    tribuchet = {
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
      # Upstream main plus the PRs we run; see its merge history.
      url = "github:ConnorBaker/tribuchet/integration";
    };

    zfs-dedup = {
      flake = false;
      url = "github:Mic92/zfs-dedup";
    };
  };

  outputs =
    inputs:
    let
      inherit (inputs.flake-parts.lib) mkFlake;
      inherit (inputs.nixpkgs) lib;
      inherit (lib.attrsets) genAttrs;

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      overlays = [
        # Misc tools
        inputs.nix-direnv.overlays.default
        (import ./overlays/infrastructure.nix inputs)
        inputs.nil.overlays.default
        (_: prev: {
          nil = prev.nil.overrideAttrs (_: {
            doCheck = false;
          });
        })
        inputs.nix.overlays.default
        inputs.nix-optimization.overlays.default
        (final: prev: {
          nixVersions = prev.nixVersions.extend (
            finalNixVersions: _: {
              latest = final.nix; # Provided by nix overlay
              stable = finalNixVersions.latest;
            }
          );
        })
      ];

      config.allowUnfree = true;

      mkNixpkgs =
        system:
        import inputs.nixpkgs {
          inherit config overlays;
          localSystem.system = system;
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

          # nix-cli does not include upstream's test gate. Check the same
          # patched, optimized libraries used by the system and its plugins.
          checks =
            lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
              nix-util = pkgs.nix.components.nix-util-tests.tests.run;
              nix-store = pkgs.nix.components.nix-store-tests.tests.run;
              nix-expr = pkgs.nix.components.nix-expr-tests.tests.run;
              nix-fetchers = pkgs.nix.components.nix-fetchers-tests.tests.run;
              nix-flake = pkgs.nix.components.nix-flake-tests.tests.run;
              nix-eval-jobs = pkgs.callPackage (inputs.nix-eval-jobs + "/dev/functional-tests.nix") {
                nix = pkgs.nix.unwrapped;
                nix-eval-jobs = pkgs.nixEvalJobsUnwrapped;
              };
              nix-eval-jobs-tarmac = pkgs.callPackage (inputs.nix-eval-jobs + "/dev/functional-tests.nix") { };
              tarmac-inherited-plugins =
                pkgs.runCommand "tarmac-inherited-plugins"
                  {
                    nativeBuildInputs = [ pkgs.jq ];
                  }
                  ''
                    bash ${inputs.nix-optimization}/tests/tarmac-inheritance.sh \
                      ${pkgs.nix}/bin/nix \
                      ${pkgs.nix-eval-jobs}/bin/nix-eval-jobs \
                      ${pkgs.nix.plugin} \
                      ${pkgs.nix-grpc-store}/lib/nix/plugins
                    touch "$out"
                  '';
              tarmac-sandbox-cache =
                pkgs.runCommand "tarmac-sandbox-cache"
                  {
                    nativeBuildInputs = [
                      pkgs.nix
                      pkgs.nix-eval-jobs
                      pkgs.jq
                    ];
                  }
                  ''
                    unset XDG_CACHE_HOME
                    # Instantiate into a private store, without contacting the
                    # host daemon or changing the sandbox's unwritable HOME.
                    export NIX_REMOTE=local
                    export NIX_STORE_DIR="$NIX_BUILD_TOP/store"
                    export NIX_STATE_DIR="$NIX_BUILD_TOP/state"
                    export NIX_LOG_DIR="$NIX_BUILD_TOP/log"
                    export NIX_CONF_DIR="$NIX_BUILD_TOP/conf"
                    mkdir -p "$NIX_CONF_DIR"
                    nix --extra-experimental-features nix-command eval --offline --raw --expr \
                      'builtins.readFile (builtins.toFile "cache-check" "sandbox-cache-ok")' > cli-result
                    test "$(cat cli-result)" = sandbox-cache-ok
                    nix-eval-jobs --workers 1 --expr \
                      '{ sample = derivation { name = "cache-check"; system = "${system}"; builder = "/bin/sh"; }; }' > jobs.jsonl
                    jq -e '.attr == "sample" and .error == null and (.drvPath | endswith(".drv"))' jobs.jsonl
                    test -d "$NIX_BUILD_TOP/.cache/nix/tarmac"
                    touch "$out"
                  '';
            }
            // lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
              networking-reload = pkgs.callPackage ./tests/networking-reload.nix {
                networkFiles = builtins.mapAttrs (
                  _: unit: unit.text
                ) inputs.self.nixosConfigurations.nixos-desktop.config.systemd.network.units;
              };
              # zfs-dedup on nixos-ext's ZFS (the FIDEDUPERANGE backport), and
              # the stock pair as its negative control.
              zfs-fideduperange = pkgs.callPackage ./tests/zfs-fideduperange.nix {
                hostConfig = inputs.self.nixosConfigurations.nixos-ext.config;
                patched = true;
              };
              zfs-fideduperange-stock = pkgs.callPackage ./tests/zfs-fideduperange.nix {
                hostConfig = inputs.self.nixosConfigurations.nixos-ext.config;
                patched = false;
              };
            }
            // (
              let
                zts =
                  patched: suffix: tests:
                  pkgs.callPackage ./tests/zfs-fideduperange-zts.nix {
                    hostConfig = inputs.self.nixosConfigurations.nixos-ext.config;
                    inherit patched suffix tests;
                  };
                # The commit's own ZTS cases.
                dedupeTests = [
                  "block_cloning_fideduperange"
                  "block_cloning_fideduperange_blksz"
                  "block_cloning_fideduperange_compress"
                  "block_cloning_fideduperange_differs"
                  "block_cloning_fideduperange_eof"
                  "block_cloning_fideduperange_mtime"
                  "block_cloning_fideduperange_partial"
                  "block_cloning_fideduperange_replay"
                  "block_cloning_fideduperange_sparse"
                  "block_cloning_fideduperange_subblock"
                  "block_cloning_fideduperange_tail"
                  "block_cloning_disabled_fideduperange"
                ];
                # 2.4.4's existing block_cloning cases: the backport reworks
                # zfs_clone_range() and the two fixes change it and
                # dmu_read_l0_bps(), which FICLONE and copy_file_range use.
                cloneTests = [
                  "block_cloning_clone_mmap_cached"
                  "block_cloning_copyfilerange"
                  "block_cloning_copyfilerange_partial"
                  "block_cloning_copyfilerange_fallback"
                  "block_cloning_disabled_copyfilerange"
                  "block_cloning_copyfilerange_cross_dataset"
                  "block_cloning_cross_enc_dataset"
                  "block_cloning_copyfilerange_fallback_same_txg"
                  "block_cloning_replay"
                  "block_cloning_replay_encrypted"
                  "block_cloning_lwb_buffer_overflow"
                  "block_cloning_clone_mmap_write"
                  "block_cloning_rlimit_fsize"
                  "block_cloning_large_offset"
                  "block_cloning_after_device_removal"
                  "block_cloning_after_trunc"
                  "block_cloning_ficlone"
                  "block_cloning_ficlonerange"
                  "block_cloning_ficlonerange_partial"
                  "block_cloning_disabled_ficlone"
                  "block_cloning_disabled_ficlonerange"
                ];
              in
              lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
                zfs-fideduperange-zts = zts true "dedupe" dedupeTests;
                zfs-fideduperange-zts-stock = zts false "dedupe" dedupeTests;
                zfs-fideduperange-zts-clone = zts true "clone" cloneTests;
              }
            );

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
              nixfmt.enable = true;

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
                inputs.tribuchet.nixosModules.default
                inputs.nix-grpc-store.nixosModules.client
                inputs.nix-grpc-store.nixosModules.server
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
            inputs.jetpack-nixos.nixosModules.default
            ./devices/nixos-orin
          ];
        };
    };
}
