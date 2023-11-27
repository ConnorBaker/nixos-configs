{
  # When we use the overlay attribute of a flake, we fetch the dependency as a flake.
  # If there's no overlay, we essentially build our own, so we just fetch the source
  # as a tarball.
  inputs = {
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

    nixfmt = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:piegamesde/nixfmt/4ef4c39acd501a9a1b06b3a151b36be5daebcef3";
    };

    nixos-generators = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/nixos-generators";
    };

    nixpkgs-review = {
      flake = false;
      url = "github:mic92/nixpkgs-review";
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

    statix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nerdypepper/statix";
    };

    treefmt-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/treefmt-nix";
    };
  };

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
              let
                cfg = import ./nixpkgs-overlays.nix { inherit inputs inputs'; } { inherit lib; };
                nixpkgs = import inputs.nixpkgs ({ inherit system; } // cfg.nixpkgs);
              in
              {
                _module.args.pkgs = nixpkgs;
              };
          }
          inputs.treefmt-nix.flakeModule
          inputs.pre-commit-hooks-nix.flakeModule
        ];

        perSystem =
          { config, pkgs, ... }:
          {
            # Helpful for inspecting attributes
            legacyPackages = pkgs;

            packages = {
              gpt-efi-iso-installer = inputs.nixos-generators.nixosGenerate {
                inherit pkgs;
                modules = [
                  (
                    { lib, ... }:
                    {
                      services.sshd.enable = true;
                      services.nginx.enable = true;

                      networking.firewall.allowedTCPPorts = [ 80 ];

                      system.stateVersion = lib.version;

                      users.users.root.password = "nixos";
                      services.openssh.settings.PermitRootLogin = lib.mkDefault "yes";
                      services.getty.autologinUser = lib.mkDefault "root";
                    }
                  )
                ];
                format = "gpt-efi-iso-installer";
                customFormats.gpt-efi-iso-installer = {
                  imports = [
                    (
                      { lib, modulesPath, ... }:
                      {
                        imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
                        isoImage = {
                          squashfsCompression = "zstd -Xcompression-level 19";
                          makeUsbBootable = lib.mkForce true;
                          makeBiosBootable = lib.mkForce false;
                          makeEfiBootable = lib.mkForce true;
                        };
                        # override installation-cd-minimal and enable wpa and sshd start at boot
                        systemd.services.wpa_supplicant.wantedBy = lib.mkForce [ "multi-user.target" ];
                        systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
                      }
                    )
                  ];
                  formatAttr = "isoImage";
                  fileExtension = ".iso";
                };
              };
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
            # Common configuration for all bootable images.
            commonConfigModule =
              system:
              { lib, modulesPath, ... }:
              {
                imports = [ inputs.nixos-generators.nixosModules.all-formats ];
                # fileSystems = {
                #   "/" = {
                #     device = "/dev/disk/by-label/nixos";
                #     autoResize = true;
                #     fsType = "ext4";
                #   };
                #   "/boot" = {
                #     device = "/dev/disk/by-label/ESP";
                #     fsType = "vfat";
                #   };
                # };

                # boot = {
                #   growPartition = true;
                #   kernelParams = ["console=ttyS0"];
                #   loader = {
                #     efi.canTouchEfiVariables = true;
                #     grub = {
                #       device = "nodev";
                #       efiSupport = true;
                #       efiInstallAsRemovable = true;
                #     };
                #     systemd-boot.enable = true;
                #   };
                #   initrd.availableKernelModules = ["uas"];
                # };

                # networking.hostName = "nixos-bootable";

                # nixpkgs = {
                #   config.allowUnfree = true;
                #   hostPlatform.system = system;
                # };

                # isoImage = {
                #   squashfsCompression = "zstd -Xcompression-level 19";
                #   makeBootable = true;
                #   makeBiosBootable = false;
                #   makeEfiBootable = true;
                # };
              };
          in
          {
            nixos-desktop = withSystem "x86_64-linux" (
              { inputs', ... }:
              inputs.nixpkgs.lib.nixosSystem {
                modules = [
                  (import ./nixpkgs-overlays.nix { inherit inputs inputs'; })
                  ./devices/nixos-desktop
                ];
              }
            );

            # TODO: nixos-ext and nixos-build01 can be factored out into a module for systems running ZFS with rpool.
            nixos-ext = withSystem "x86_64-linux" (
              { inputs', ... }:
              inputs.nixpkgs.lib.nixosSystem {
                modules = [
                  (import ./nixpkgs-overlays.nix { inherit inputs inputs'; })
                  ./devices/nixos-ext
                ];
              }
            );

            nixos-build01 = withSystem "x86_64-linux" (
              { inputs', ... }:
              inputs.nixpkgs.lib.nixosSystem {
                modules = [
                  (import ./nixpkgs-overlays.nix { inherit inputs inputs'; })
                  ./devices/nixos-build01
                ];
              }
            );
          };
      }
    );
}
