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

    jetpack-nixos = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:anduril/jetpack-nixos";
    };

    nil = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:oxalica/nil";
    };

    nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:NixOS/nix/2.18-maintenance";
    };

    nix-direnv = {
      inputs = {
        flake-utils.follows = "flake-utils";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:nix-community/nix-direnv";
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

    # nixos/systemd-stage1: fix initrd build with zfsUnstable #255583: https://github.com/NixOS/nixpkgs/pull/255583
    nixpkgs.url = "github:NixOS/nixpkgs/fd6901755debe65abf8102a61dbfb44dd09fa1dc";
    # nixpkgs.url = "github:ConnorBaker/nixpkgs/feat/nvidia-dcgm-prometheus-exporter-module";

    nixos-images = {
      inputs = {
        nixos-unstable.follows = "nixpkgs";
        nixos-2305.follows = "nixpkgs";
      };
      url = "github:nix-community/nixos-images";
    };

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
      inputs = {
        nixpkgs-stable.follows = "nixpkgs";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:Mic92/sops-nix";
    };

    statix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nerdypepper/statix";
    };

    treefmt-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/treefmt-nix";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({
      self,
      withSystem,
      ...
    }: {
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.pre-commit-hooks-nix.flakeModule
        ./nixpkgs-overlays.nix
      ];

      perSystem = {
        config,
        pkgs,
        ...
      }: {
        # Helpful for inspecting attributes
        legacyPackages = pkgs;
        packages = {
          nixos-orin-kexec-tarball = self.nixosConfigurations.nixos-orin-kexec.config.system.build.kexecTarball;
        };
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
            alejandra.enable = true;

            # Shell
            shellcheck.enable = true;
            shfmt.enable = true;

            # YAML
            yamlfmt.enable = true;
          };
          # (ab)use options to pass a hidden file to be formatted.
          # See https://github.com/numtide/treefmt/issues/153.
          settings.formatter.yamlfmt.options = [".sops.yaml"];
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

        nixos-orin = withSystem "aarch64-linux" ({pkgs, ...}:
          inputs.nixpkgs.lib.nixosSystem {
            inherit pkgs;
            modules = [
              inputs.jetpack-nixos.nixosModules.default
              inputs.sops-nix.nixosModules.sops
              inputs.disko.nixosModules.disko
              # Not using ZFS or impermanence on Orin.
              ./devices/nixos-orin
            ];
          });

        nixos-orin-kexec = withSystem "aarch64-linux" ({
          pkgs,
          system,
          ...
        }:
          inputs.nixpkgs.lib.nixosSystem {
            # inherit pkgs;
            pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [inputs.jetpack-nixos.overlays.default];
            };
            modules = [
              {system.kexec-installer.name = "nixos-kexec-installer-noninteractive";}
              inputs.nixos-images.nixosModules.noninteractive
              inputs.nixos-images.nixosModules.kexec-installer
              inputs.jetpack-nixos.nixosModules.default
              # Unset some things that are set by default in the kexec-installer module.
              # This is done largely to ensure that there are no references to ZFS, which the jetpack kernel doesn't support.
              # We can't use an in-tree kernel either because then the kexec-installer won't work.
              ({
                config,
                lib,
                pkgs,
                ...
              }: {
                boot = {
                  kernelModules = lib.mkOverride 45 ["nvgpu" "bridge" "macvlan" "tap" "tun" "loop" "atkbd"];
                  kernelPackages = lib.mkOverride 45 pkgs.nvidia-jetpack.kernelPackages;
                  extraModulePackages = lib.mkOverride 45 [config.boot.kernelPackages.nvidia-display-driver];
                };
                environment.defaultPackages = lib.mkOverride 45 [
                  pkgs.rsync
                  pkgs.parted
                  pkgs.gptfdisk
                ];
                hardware = {
                  enableRedistributableFirmware = lib.mkOverride 45 true;
                  nvidia-jetpack = {
                    enable = true;
                    som = "orin-agx";
                    carrierBoard = "devkit";
                  };
                };
              })
            ];
          });
      };
    });
}
