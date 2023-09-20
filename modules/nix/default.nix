{
  config,
  lib,
  ...
}: let
  # Common configuration for all machines.
  # Maps host names to machine architecture.
  # hostNameToSystem :: AttrSet String (AttrSet String Any)
  hostNameToConfig = {
    nixos-build01 = {
      speedFactor = 8;
      systems = [
        "x86_64-linux" # Physical
        "aarch64-linux" # Emulated
      ];
    };
    nixos-desktop = {
      speedFactor = 8;
      systems = [
        "x86_64-linux" # Physical
        "aarch64-linux" # Emulated
      ];
    };
    nixos-ext = {
      speedFactor = 8;
      systems = [
        "x86_64-linux" # Physical
        "aarch64-linux" # Emulated
      ];
    };
    nixos-orin = {
      speedFactor = 1;
      systems = [
        "aarch64-linux" # Physical
      ];
    };
  };
  maxJobs = 2;
  supportedFeatures = [
    "benchmark"
    "big-parallel"
    "kvm"
    "nixos-test"
  ];
  # Functions to generate machine-specific configuration.
  # machineBoilerplate :: String -> AttrSet String Any -> AttrSet String Any
  machineBoilerplate = hostName:
    lib.attrsets.recursiveUpdate {
      inherit hostName maxJobs supportedFeatures;
      protocol = "ssh-ng";
      sshKey = "/etc/ssh/id_nix_ed25519";
      sshUser = "nix";
    };
  # A machine should not have itself as a remote builder.
  irreflexive = hostName: _: hostName != config.networking.hostName;
in {
  imports = [
    ./secrets.nix
  ];

  nix = {
    buildMachines = lib.trivial.pipe hostNameToConfig [
      # AttrSet String (AttrSet String Any) -> AttrSet String (AttrSet String Any)
      (lib.attrsets.filterAttrs irreflexive)
      # AttrSet String (AttrSet String Any) -> AttrSet String (AttrSet String Any)
      (lib.attrsets.mapAttrs machineBoilerplate)
      # AttrSet String (AttrSet String Any) -> List (AttrSet String Any)
      lib.attrsets.attrValues
    ];
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedPriority = 7;
    distributedBuilds = true;
    settings = {
      accept-flake-config = true;
      auto-allocate-uids = true;
      auto-optimise-store = true;
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
      max-jobs = maxJobs;
      max-substitution-jobs = 256; # Nix >= 2.16
      require-drop-supplementary-groups = true; # Nix >= 2.17
      # NOTE: Disabled because nixpkgs-review requires impure evaluation.
      # restrict-eval = true;
      system-features = supportedFeatures;
      trusted-users = ["root" "@nixbld" "@wheel"];
      use-cgroups = true;
      use-xdg-base-directories = true;
    };
  };

  users.users.nix = {
    description = "Nix account";
    extraGroups = ["wheel"];
    isNormalUser = true;
    openssh.authorizedKeys.keyFiles = [./keys/id_nix_ed25519.pub];
  };
}
