{lib, ...}: {
  nix = {
    buildMachines = [
      {
        hostName = "52.249.197.56";
        maxJobs = 1;
        protocol = "ssh-ng";
        # base64 -w0 - <<< "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL84WOm0Lij8ctWc0bcfx42F/ZTYO5/DD/OXzAtLBzSA"
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUw4NFdPbTBMaWo4Y3RXYzBiY2Z4NDJGL1pUWU81L0REL09YekF0TEJ6U0EK";
        sshKey = "/home/connorbaker/.ssh/id_ed25519";
        sshUser = "connorbaker";
        supportedFeatures = [
          "benchmark"
          "big-parallel"
          "kvm"
          "nixos-test"
        ];
        system = "x86_64-linux";
      }
    ];
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedPriority = 7;
    distributedBuilds = true;
    settings = {
      accept-flake-config = true;
      auto-allocate-uids = true;
      allow-import-from-derivation = false;
      builders-use-substitutes = true;
      cores = 0;
      experimental-features = [
        "auto-allocate-uids"
        "ca-derivations"
        "cgroups"
        "flakes"
        "nix-command"
        "no-url-literals"
        "repl-flake"
      ];
      fsync-metadata = false;
      http-connections = 0;
      keep-derivations = true;
      keep-outputs = true;
      max-jobs = 1;
      max-substitution-jobs = 1024;
      # NOTE: Disabled because this requires Nix >= 2.17.
      # require-drop-supplementary-groups = true;
      # NOTE: Disabled because nixpkgs-review requires impure evaluation.
      # restrict-eval = true;
      system-features = [
        "benchmark"
        "big-parallel"
        "kvm"
        "nixos-test"
      ];
      trusted-users = ["root" "@nixbld" "@wheel"];
      use-cgroups = true;
      # NOTE: Disabled because it makes every nix command print:
      # warning: Nix search path entry '/etc/nixos/configuration.nix' does not exist, ignoring
      # TODO(@connorbaker): File a bug report?
      # use-xdg-base-directories = true;
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
