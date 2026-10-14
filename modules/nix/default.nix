{
  config,
  lib,
  ...
}:
let
  inherit (lib.attrsets)
    attrNames
    attrValues
    genAttrs
    mapAttrs
    ;
  inherit (lib.strings) concatMapStringsSep;

  inventory = import ../../inventory.nix;
  nixPrivateKey = "ssh/id_nix_ed25519";

  # Common configuration for all machines.
  baselineSupportedFeatures = [
    "benchmark"
    "big-parallel"
    "ca-derivations"
    "kvm"
    "nixos-test"
    "recursive-nix"
    # Every host runs auto-allocate-uids with cgroups (settings below).
    "uid-range"
  ];

  # The inventory supplies builder metadata without evaluating other systems.
  hostNameToBuildMachineConfig =
    let
      mkBuildMachineConfig = hostName: machine: {
        hostName =
          if config.programs.nix-grpc-store.enable then
            "grpc://${hostName}.${inventory.tailnet}:50051?insecure=1&connect-timeout=5"
          else
            hostName + "?max-connections=1&want-mass-query=true";
        supportedFeatures = baselineSupportedFeatures ++ machine.features;
        # Builds this client keeps in flight there; hook builds do not take
        # local build slots, so this alone bounds them.
        maxJobs = machine.maxJobs or 3;
        # Ext schedules CPU jobs through Tribuchet. Direct gRPC builders
        # serve GPU jobs, which Tribuchet workers cannot advertise.
        mandatoryFeatures =
          machine.mandatoryFeatures or (lib.optionals (builtins.elem "cuda" machine.features) [ "cuda" ]);
        protocol = if config.programs.nix-grpc-store.enable then null else "ssh-ng";
        speedFactor = 1;
        sshKey =
          if config.programs.nix-grpc-store.enable then null else config.sops.secrets.${nixPrivateKey}.path;
        inherit (machine) systems;
      };
    in
    mapAttrs mkBuildMachineConfig hostNameToBuildMachineDefinitions;

  hostNameToBuildMachineDefinitions = inventory.hosts;

  # Hosts reached over SSH (known host keys live under devices/).
  sshHostNames = attrNames (
    lib.filterAttrs (_: machine: machine.nixos or true) hostNameToBuildMachineDefinitions
  );
in
{
  imports = [ ../services/tribuchet.nix ];
  networking.hosts = lib.mapAttrs' (hostName: machine: {
    name = machine.lan.ipv4;
    value = [ hostName ];
  }) (lib.filterAttrs (_: machine: machine ? lan) inventory.hosts);

  nix = {
    # Use flakes for everything
    channel.enable = false;

    buildMachines = attrValues (
      lib.filterAttrs (
        hostName: machine:
        hostName != config.networking.hostName
        && (hostName == inventory.hub || builtins.elem "cuda" machine.supportedFeatures)
        # Non-NixOS builders are reachable over gRPC only.
        && (
          config.programs.nix-grpc-store.enable || hostNameToBuildMachineDefinitions.${hostName}.nixos or true
        )
      ) hostNameToBuildMachineConfig
    );

    distributedBuilds = true;

    settings = {
      builders-use-substitutes = true;
      connect-timeout = 5; # Don't wait forever for a remote builder to respond.
      # Builds take a fresh uid slot (and, for uid-range, a 65536-uid
      # range) instead of a static nixbld account, and run in their own
      # cgroup, so they are accounted and killed as a unit.
      auto-allocate-uids = true;
      use-cgroups = true;
      experimental-features = [
        "auto-allocate-uids"
        "ca-derivations"
        "cgroups"
        "dynamic-derivations"
        "flakes"
        "git-hashing"
        "nix-command"
        "read-only-local-store"
        "recursive-nix"
      ];
      fallback = true;
      fsync-metadata = false;
      http-connections = 32;
      log-lines = 100;
      max-jobs = 3;
      max-substitution-jobs = 32;
      require-drop-supplementary-groups = true;
      # NixOS contributes benchmark/big-parallel/kvm/nixos-test and gccarch.
      # Keep the full baseline above for remote builder advertisements.
      system-features = [
        "ca-derivations"
        "recursive-nix"
        "uid-range"
      ]
      ++ lib.optionals (!config.programs.nix-required-mounts.presets.nvidia-gpu.enable) (
        inventory.hosts.${config.networking.hostName}.features or [ ]
      );
      trusted-users = [
        "@wheel"
      ];
      use-xdg-base-directories = true;
      warn-dirty = false;
    };
  };

  programs.ssh = {
    extraConfig = concatMapStringsSep "\n" (hostName: ''
      Match host ${hostName}
        PubkeyAcceptedKeyTypes ssh-ed25519
        ServerAliveInterval 60
        IPQoS throughput
        IdentityFile ${config.sops.secrets.${nixPrivateKey}.path}
    '') sshHostNames;
    knownHosts = genAttrs sshHostNames (hostName: {
      publicKeyFile = ../.. + "/devices/${hostName}/keys/ssh_host_ed25519_key.pub";
    });
  };

  sops.secrets.${nixPrivateKey} = {
    mode = "0400";
    path = "/etc/${nixPrivateKey}";
    sopsFile = ./secrets.yaml;
  };

  users.users.root.openssh.authorizedKeys.keyFiles = [ ./keys/id_nix_ed25519.pub ];
}
