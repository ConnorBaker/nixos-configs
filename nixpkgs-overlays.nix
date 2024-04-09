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
      # Override the default version(s) of Nix.
      (final: prev: {
        nixStable = final.nixVersions.stable;
        nixUnstable = final.nixVersions.unstable;
        nixVersions = prev.nixVersions.extend (
          nixFinal: nixPrev: {
            stable = nixFinal.unstable;
            unstable = nixPrev.unstable.overrideAttrs (
              finalAttrs: prevAttrs: {
                version = "${finalAttrs.src.rev}${finalAttrs.VERSION_SUFFIX}";
                src = final.fetchFromGitHub {
                  owner = "NixOS";
                  repo = "nix";
                  rev = "2.21.2";
                  hash = "sha256-ObaVDDPtnOeIE0t7m4OVk5G+OS6d9qYh+ktK67Fe/zE=";
                };
              }
            );
          }
        );
      })
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
      inputs.nix-ld-rs.overlays.default
      (_: _: { inherit (inputs'.histodu.packages) histodu; })
    ];
  };
}
