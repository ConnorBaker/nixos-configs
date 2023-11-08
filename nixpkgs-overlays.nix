# Arguments from flake.parts
{
  inputs,
  inputs',
  ...
}:
# Arguments from NixOS module system
{lib, ...}: {
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
  ];
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      # Override the Nix build used
      inputs.nix.overlays.default
      # Swap out older versions of Nix with newer ones.
      # Don't go too far back, because some packages truly haven't been updated.
      # For example, nixos-options has header errors.
      (final: prev: {
        nixVersions = prev.nixVersions.extend (
          _: _:
            lib.attrsets.genAttrs
            ["nix_2_17" "stable" "unstable"]
            (lib.const final.nix)
        );
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
  };
}
