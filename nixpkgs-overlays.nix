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
          inherit (final.haskell.lib) justStaticExecutables;
          hlib = final.haskell.lib.compose;
        in
        {
          haskell = prev.haskell // {
            packageOverrides = hsFinal: _: {
              nix-output-monitor =
                let
                  golden-tests = import "${inputs.nix-output-monitor}/test/golden/all.nix";
                  cleanSelf = lib.sourceFilesBySuffices inputs.nix-output-monitor [
                    ".hs"
                    ".cabal"
                    "stderr"
                    "stdout"
                    "stderr.json"
                    "stdout.json"
                    ".zsh"
                    "LICENSE"
                    "CHANGELOG.md"
                    "default.nix"
                  ];
                in
                lib.pipe { } [
                  (hsFinal.callPackage inputs.nix-output-monitor)
                  hsFinal.buildFromCabalSdist
                  (hlib.appendConfigureFlag "--ghc-option=-Werror")
                  (hlib.overrideCabal {
                    src = cleanSelf;
                    preCheck = ''
                      # ${lib.concatStringsSep ", " (golden-tests ++ map (x: x.drvPath) golden-tests)}
                      export TESTS_FROM_FILE=true;
                    '';
                    buildTools = [ final.installShellFiles ];
                    postInstall = ''
                      ln -s nom "$out/bin/nom-build"
                      ln -s nom "$out/bin/nom-shell"
                      chmod a+x $out/bin/nom-shell
                      installShellCompletion --zsh --name _nom-build completions/completion.zsh
                    '';
                  })
                ];
              nixfmt = lib.pipe { } [
                (hsFinal.callCabal2nix "nixfmt" inputs.nixfmt)
                hlib.doJailbreak
              ];
            };
          };
          nixVersions = prev.nixVersions.extend (
            _: _: {
              stable = final.nix;
              unstable = final.nix;
            }
          );
          nix-output-monitor = justStaticExecutables final.haskellPackages.nix-output-monitor;
          nixfmt = justStaticExecutables final.haskellPackages.nixfmt;
          nixpkgs-review = final.callPackage inputs.nixpkgs-review { withSandboxSupport = true; };
        }
      )
    ];
  };
}
