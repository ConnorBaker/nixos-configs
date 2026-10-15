inputs: final: prev:
let
  # PR #204: drain active uploads, retain their assignments, and retry when
  # a worker leaves. Keep the reviewed diff immutable until upstream merges it.
  grpcDrainFix = final.fetchpatch {
    name = "nix-grpc-store-pr204.patch";
    url = "https://github.com/Mic92/nix-grpc-store/compare/1136edcf65413ab721385ed599b11e79e291dacc...62b2c8bc0bdf055130fd17f935f3e3210fe8c737.diff";
    includes = [ "src/*" ];
    # The PR predates 1136edc's StorePathSet upload API. Preserve that
    # upstream change while adapting the PR's old and new call sites.
    postFetch = ''
      substituteInPlace "$out" \
        --replace-fail 'uploadDrvClosure(evalStore, job.drvPath,' \
                       'uploadDrvClosure(evalStore, {job.drvPath},'
    '';
    hash = "sha256-YRlzkEWcYBndSiCYXCr2IAJXuKDZnDKD8EJupTf3gaU=";
  };
  # Nix PR #16433 passes the evaluation store through queryMissing. A gRPC
  # daemon cannot see that store, so traverse on the client as RemoteStore does.
  grpcEvalStoreFix = ../packages/nix-grpc-store-query-missing-eval-store.patch;
  patchGrpc =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        grpcDrainFix
        grpcEvalStoreFix
      ];
    });
in
{
  histodu = final.callPackage ../packages/histodu.nix { source = inputs.histodu; };
  zfs-dedup = final.callPackage (inputs.zfs-dedup + "/nix/package.nix") { };
  tribuchet = final.callPackage (inputs.tribuchet + "/nix/package.nix") {
    craneLib = inputs.tribuchet.inputs.crane.mkLib final;
  };
  # The daemon and plugin must use the same Nix component libraries.
  nixGrpcPackages =
    (final.callPackage (inputs.nix-grpc-store + "/nix/packages") {
      nixPackages = final.nix.libs;
    }).overrideScope
      (
        grpcFinal: grpcPrev: {
          default = patchGrpc grpcPrev.default;
          pluginFor = nix: patchGrpc (grpcPrev.pluginFor nix);
          imagePackage = patchGrpc grpcPrev.imagePackage;
          wrapNix = grpcFinal.callPackage (inputs.nix-grpc-store + "/nix/packages/wrap-nix.nix") {
            callPackage = file: args: patchGrpc (grpcFinal.callPackage file args);
          };
        }
      );
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
