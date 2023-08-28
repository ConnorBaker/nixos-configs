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
        (final: prev: {
          nixVersions = prev.nixVersions.extend (_: _: {
            stable = prev.nix;
            unstable = prev.nix;
          });
        })
        # Nil Nix language server
        inputs.nil.overlays.nil
        # Nix linker fix for third-party packages
        inputs.nix-ld-rs.overlays.default
        # External nixpkgs-review
        (final: _: {
          nixpkgs-review = final.callPackage inputs.nixpkgs-review {withSandboxSupport = true;};
        })
        # External nix-output-manager
        (_: _: {
          # TODO(@connorbaker): Does not override the package in haskellPackages.
          nix-output-manager = inputs'.nix-output-manager.packages.default;
        })
        # External Nix formatter
        inputs.alejandra.overlays.default
      ];
      config.allowUnfree = true;
    };
  };
}
