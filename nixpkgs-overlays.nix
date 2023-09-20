{inputs, ...}: {
  perSystem = {
    inputs',
    lib,
    system,
    ...
  }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
        # https://github.com/ivmai/bdwgc/issues/541
        (
          _: prev:
            lib.attrsets.optionalAttrs prev.stdenv.hostPlatform.isAarch64 {
              boehmgc = prev.boehmgc.overrideAttrs (_: {
                doCheck = false;
              });
            }
        )
        # Override the Nix build used
        (final: prev: {
          nix = prev.nixVersions.nix_2_17;
          nixVersions = prev.nixVersions.extend (
            _: _:
              lib.attrsets.genAttrs
              ["nix_2_17" "stable" "unstable"]
              (lib.const final.nix)
          );
        })
        # Add jetson nixpkgs
        inputs.jetpack-nixos.overlays.default
        # External nixpkgs-review
        (final: _: {
          nixpkgs-review = final.callPackage inputs.nixpkgs-review {withSandboxSupport = true;};
        })
        # External nix-output-manager
        (_: _: {
          # TODO(@connorbaker): Does not override the package in haskellPackages.
          nix-output-manager = inputs'.nix-output-manager.packages.default;
        })
        # External nix-direnv
        inputs.nix-direnv.overlay
        # External Nix tools
        inputs.alejandra.overlays.default
        inputs.deadnix.overlays.default
        inputs.nil.overlays.nil
        inputs.nix-ld-rs.overlays.default
        inputs.statix.overlays.default
      ];
      config.allowUnfree = true;
    };
  };
}
