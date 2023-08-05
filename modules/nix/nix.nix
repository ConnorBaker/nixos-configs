{
  nix = {
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedPriority = 7;
    settings = {
      accept-flake-config = true;
      auto-allocate-uids = true;
      auto-optimise-store = true;
      allow-import-from-derivation = false;
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
      max-substitution-jobs = 256; # Nix >= 2.16
      require-drop-supplementary-groups = true; # Nix >= 2.17
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
      use-xdg-base-directories = true;
    };
  };
}
