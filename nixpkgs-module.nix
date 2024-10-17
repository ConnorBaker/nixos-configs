# Arguments from flake.parts
{ inputs, system, ... }:
{
  nixpkgs = {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      # Have HerculesCI use the version of Nix everything else does
      (final: prev: {
        haskellPackages = prev.haskellPackages.override {
          overrides = _: hsPrev: {
            # doJailbreak on the hercules-ci-cnix-store to relax dependency on Nix version
            hercules-ci-cnix-store = final.haskell.lib.doJailbreak hsPrev.hercules-ci-cnix-store;
          };
        };
      })
      # Misc tools
      inputs.nix-direnv.overlays.default
      (_: _: { inherit (inputs.histodu.packages.${system}) histodu; })
      # Overlay for Caddy
      (
        final: prev:
        prev.lib.filesystem.packagesFromDirectoryRecursive {
          inherit (final) callPackage;
          directory = ./packages;
        }
      )
    ];
  };
}
