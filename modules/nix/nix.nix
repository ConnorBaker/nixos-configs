{lib, ...}: {
  nix = {
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedPriority = 7;
    settings = {
      accept-flake-config = true;
      allow-import-from-derivation = false;
      cores = 0;
      experimental-features = [
        "flakes"
        "nix-command"
        # "no-url-literals" # Somehow use is still prevalent
      ];
      fsync-metadata = false;
      http-connections = 0;
      keep-derivations = true;
      keep-outputs = true;
      max-jobs = 8;
      max-substitution-jobs = 1024;
      system-features = [
        "benchmark"
        "big-parallel"
        "kvm"
        "nixos-test"
      ];
      trusted-users = ["root" "@nixbld" "@wheel"];
    };
  };

  nixpkgs.overlays = [
    # Need newer version of Nix supporting max-substitution-jobs
    (_: prev: {
      nix =
        if lib.strings.versionAtLeast prev.nix.version "2.16"
        then prev.nix
        else prev.nixVersions.nix_2_16;
    })
  ];
}
