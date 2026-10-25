inputs: final: prev:
{
  histodu = final.callPackage ../packages/histodu.nix { source = inputs.histodu; };
  zfs-dedup = final.callPackage (inputs.zfs-dedup + "/nix/package.nix") { };
  tribuchet = final.callPackage (inputs.tribuchet + "/nix/package.nix") {
    craneLib = inputs.tribuchet.inputs.crane.mkLib final;
  };
  # The daemon and plugin must use the same Nix component libraries. The
  # input is ConnorBaker/nix-grpc-store's integration branch: upstream main
  # with the PRs and patches we run merged in, so no patches here.
  nixGrpcPackages = final.callPackage (inputs.nix-grpc-store + "/nix/packages") {
    nixPackages = final.nix.libs;
  };
  nix-grpc-store = final.nixGrpcPackages.default;
  # Keep main's separate-store/scheduling fixes, porting the nix-next API
  # changes onto it rather than reverting to that branch's older base.
  nixEvalJobsUnwrapped =
    (prev.nix-eval-jobs.override {
      nixComponents = final.nix.components;
      boost = final.nix.components.boost;
      stdenv = final.llvmPackages_22.stdenv;
    }).overrideAttrs
      (old: {
        version = "${old.version}-nix-next";
        src = inputs.nix-eval-jobs;
        patches = (old.patches or [ ]) ++ [ ../packages/nix-eval-jobs-nix-next.patch ];
        doCheck = true;
        checkInputs = (old.checkInputs or [ ]) ++ [
          final.gtest
          final.nix.components.nix-util-test-support
        ];
        passthru = (old.passthru or { }) // {
          inherit (final) nix;
        };
      });
  # nix-eval-jobs embeds the evaluator, rather than launching nix. Give it
  # the same plugin and default evaluation store as the system CLI.
  nix-eval-jobs = final.symlinkJoin {
    name = "${final.nixEvalJobsUnwrapped.name}-with-tarmac";
    paths = [ final.nixEvalJobsUnwrapped ];
    nativeBuildInputs = [ final.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/nix-eval-jobs" \
        --run ${
          final.lib.escapeShellArg (
            import (inputs.nix-optimization + "/tarmac-wrapper-init.nix") {
              pluginFile = "${final.nix.plugin}/lib/nix/plugins/nix-tarmac-loader.so";
            }
          )
        } \
        --add-flags "--eval-store tarmac://"
    '';
    passthru = {
      inherit (final.nixEvalJobsUnwrapped) nixComponents;
      inherit (final) nix;
      unwrapped = final.nixEvalJobsUnwrapped;
    };
    meta = final.nixEvalJobsUnwrapped.meta;
  };
}
