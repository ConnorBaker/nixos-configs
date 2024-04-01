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
      # Use the latest version of boehmgc and libgit2
      # (final: prev: {
      #   libgit2 = prev.libgit2.overrideAttrs (
      #     finalAttrs: prevAttrs: {
      #       version = "1.8.0";
      #       src = final.fetchFromGitHub {
      #         owner = "libgit2";
      #         repo = "libgit2";
      #         rev = "v${finalAttrs.version}";
      #         hash = "sha256-eMB6msSb9BVbwKEunrXtd3chmxY13tkP+CRdZ2jFGzg=";
      #       };
      #     }
      #   );
      #   # TODO: Remove once https://github.com/NixOS/nixpkgs/pull/288435 is merged.
      #   boehmgc = prev.boehmgc.overrideAttrs (
      #     finalAttrs: prevAttrs: {
      #       version = "8.2.6";
      #       src = final.fetchFromGitHub {
      #         owner = "ivmai";
      #         repo = "bdwgc";
      #         rev = "v${finalAttrs.version}";
      #         hash = "sha256-y6hU5qU4qO9VvQvKNH9dvReCrf3+Ih2HHbF6IS1V3WQ=";
      #       };
      #     }
      #   );
      # })
      # Use the latest version of Nix.
      # inputs.nix.overlays.default
      # Upstream Nix is lagging behind the latest release of Nixpkgs;
      # some of the patches applied to boehmgc by the Nix overlay have been
      # merged upstream!
      # TODO: Remove once Nix has caught up.
      # (final: prev: {
      #   boehmgc-nix = prev.boehmgc-nix.overrideAttrs { patches = [ ]; };
      #   libgit2-nix = final.libgit2.overrideAttrs (prevAttrs: {
      #     cmakeFlags = prevAttrs.cmakeFlags or [ ] ++ [ "-DUSE_SSH=exec" ];
      #   });
      # })
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
                  rev = "2.21.1";
                  hash = "sha256-iRtvOcJbohyhav+deEajI/Ln/LU/6WqSfLyXDQaNEro=";
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
