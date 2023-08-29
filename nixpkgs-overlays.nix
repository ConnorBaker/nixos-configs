{inputs, ...}: {
  perSystem = {
    inputs',
    system,
    ...
  }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
        # Use the optimized python build
        # (final: prev: let
        #   python3 = prev.python3.override {
        #     enableOptimizations = true;
        #     enableLTO = true;
        #     reproducibleBuild = false;
        #     self = python3;
        #   };
        # in {
        #   inherit python3;
        # })
        # Override the Nix build used
        inputs.nix.overlays.default
        (_: prev: {
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
      config = {
        allowUnfree = true;
        # replaceStdenv = {pkgs, ...}: pkgs.stdenvAdapters.overrideInStdenv pkgs.fastStdenv [pkgs.libidn2];
        # replaceStdenv = {pkgs, ...}: pkgs.ccacheStdenv;
      };
      # hostPlatform = {
      #   gcc = {
      #     # TODO(@connorbaker): Raptor Lake is too new
      #     arch = "alderlake";
      #     tune = "alderlake";
      #   };
      #   inherit system;
      # };
    };
  };
}
