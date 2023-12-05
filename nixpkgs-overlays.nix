# Arguments from flake.parts
{inputs, inputs', ...}:
# Arguments from NixOS module system
{lib, ...}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    inputs.hercules-ci-agent.nixosModules.agent-service
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
            [
              "nix_2_17"
              "stable"
              "unstable"
            ]
            (lib.const final.nix)
        );
      })
      # External tools
      (
        final: prev:
        let
          inherit (final.haskell.lib) doJailbreak justStaticExecutables;
        in
        {
          haskell = prev.haskell // {
            packageOverrides =
              hsFinal: _:
              let
                inherit (hsFinal) callCabal2nix;
              in
              {
                nix-output-manager = doJailbreak (callCabal2nix "nix-output-manager" inputs.nix-output-manager {});
                nixfmt = doJailbreak (callCabal2nix "nixfmt" inputs.nixfmt {});
              };
          };
          nix-output-manager = justStaticExecutables final.haskellPackages.nix-output-manager;
          nixfmt = justStaticExecutables final.haskellPackages.nixfmt;
          nixpkgs-review = final.callPackage inputs.nixpkgs-review {withSandboxSupport = true;};
        }
      )
      # External nix-direnv
      inputs.nix-direnv.overlays.default
      # External Nix tools
      inputs.deadnix.overlays.default
      inputs.nil.overlays.nil
      inputs.nix-ld-rs.overlays.default
      inputs.statix.overlays.default
      inputs.hercules-ci-agent.overlays.default
    ];
  };
}
