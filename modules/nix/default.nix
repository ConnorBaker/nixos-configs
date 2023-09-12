{
  config,
  lib,
  ...
}: let
  # Common configuration for all machines.
  hostNames = ["nixos-ext" "nixos-build01" "nixos-desktop"];
  maxJobs = 2;
  supportedFeatures = [
    "benchmark"
    "big-parallel"
    "kvm"
    "nixos-test"
  ];
  # Functions to generate machine-specific configuration.
  machineBoilerplate = hostName: {
    inherit hostName maxJobs supportedFeatures;
    protocol = "ssh-ng";
    sshUser = "nix";
    sshKey = "/etc/ssh/id_nix_ed25519";
    # NOTE: publicHostKey is omitted, so SSH will use its regular known-hosts file when connecting.
    system = "x86_64-linux";
  };
  # A machine should not have itself as a remote builder.
  irreflexive = hostName: hostName != config.networking.hostName;
in {
  imports = [
    ./secrets.nix
  ];

  nix = {
    buildMachines = lib.trivial.pipe hostNames [
      (builtins.filter irreflexive)
      (builtins.map machineBoilerplate)
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

  # TODO: Do we need to include them as known hosts if the SSH user is Nix and not root?
  # services.openssh.knownHosts = {
  #   nixos-desktop.publicKeyFile = ../../devices/nixos-desktop/keys/id_ed25519.pub;
  #   nixos-ext.publicKeyFile = ../../devices/nixos-ext/keys/ssh_host_ed25519_key.pub;
  #   nixos-build01.publicKeyFile = ../../devices/nixos-build01/keys/ssh_host_ed25519_key.pub;
  # };

  users.users.nix = {
    description = "Nix account";
    group = "wheel";
    isSystemUser = true;
    openssh.authorizedKeys.keyFiles = [./keys/id_nix_ed25519.pub];
  };
}
