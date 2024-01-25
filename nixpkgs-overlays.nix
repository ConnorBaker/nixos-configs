# Arguments from flake.parts
{ inputs, inputs', ... }:
# Arguments from NixOS module system
{ lib, ... }:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    # inputs.hercules-ci-agent.nixosModules.agent-service
  ];
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      # Overlays
      inputs.nix.overlays.default
      inputs.hercules-ci-agent.overlays.default
      inputs.nix-direnv.overlays.default
      inputs.deadnix.overlays.default
      inputs.nil.overlays.nil
      inputs.nix-ld-rs.overlays.default
      inputs.statix.overlays.default
      # Manual overlay for version management/additional packages
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
                nix-output-monitor = doJailbreak (callCabal2nix "nix-output-monitor" inputs.nix-output-monitor { });
                nixfmt = doJailbreak (callCabal2nix "nixfmt" inputs.nixfmt { });
              };
          };
          nixVersions = prev.nixVersions.extend (
            _: _: {
              stable = final.nix;
              unstable = final.nix;
            }
          );
          nix-output-manager = justStaticExecutables final.haskellPackages.nix-output-manager;
          nixfmt = justStaticExecutables final.haskellPackages.nixfmt;
          nixpkgs-review = final.callPackage inputs.nixpkgs-review { withSandboxSupport = true; };
        }
      )
    ];
  };
}
