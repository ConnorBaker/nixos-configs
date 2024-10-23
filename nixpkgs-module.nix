# Arguments from flake.parts
{ inputs, system, ... }:
{
  nixpkgs = {
    inherit system;
    config.allowUnfree = true;
    overlays = [
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
