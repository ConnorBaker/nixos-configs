# Arguments from flake.parts
{ inputs, inputs', ... }:
# Arguments from NixOS module system
{ lib, system, ... }:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    # inputs.hercules-ci-agent.nixosModules.agent-service
  ];
  nixpkgs = {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      inputs.hercules-ci-agent.overlays.default
      inputs.nix-direnv.overlays.default
      inputs.nix-ld-rs.overlays.default
      (final: prev: {
        nix = final.nixVersions.unstable;
        nixVersions = prev.nixVersions.extend (_: _: { stable = final.nix; });
      })
    ];
  };
}
