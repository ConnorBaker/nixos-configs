# Arguments from flake.parts
{ inputs, inputs', ... }:
# Arguments from NixOS module system
{ lib, system, ... }:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
  ];
  nixpkgs = {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      inputs.nix-direnv.overlays.default
      inputs.nix-ld-rs.overlays.default
      (final: prev: {
        nix = final.nixVersions.unstable;
        nixVersions = prev.nixVersions.extend (_: _: { stable = final.nix; });
        haskellPackages = prev.haskellPackages.override {
          overrides = _: hsPrev: {
            # doJailbreak on the hercules-ci-cnix-store to relax dependency on Nix version
            hercules-ci-cnix-store = final.haskell.lib.doJailbreak hsPrev.hercules-ci-cnix-store;
          };
        };
      })
    ];
  };
}
