{inputs, ...}: {
  perSystem = {
    inputs',
    system,
    ...
  }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
        # Override the Nix build used
        inputs.nix.overlays.default
        (_: prev: {
          nixVersions = prev.nixVersions.extend (_: _: {
            stable = prev.nix;
            unstable = prev.nix;
          });
        })
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
