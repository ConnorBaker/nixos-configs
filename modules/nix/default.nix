{
  config,
  lib,
  pkgs,
  nixOptimization,
  ...
}:
let
  patchedNix = nixOptimization.packages.${pkgs.stdenv.hostPlatform.system}.tarmac-pgo;
  inherit (lib.attrsets)
    attrNames
    attrValues
    genAttrs
    mapAttrs
    ;
  inherit (lib.strings) concatMapStringsSep;

  nixPrivateKey = "ssh/id_nix_ed25519";

  # Common configuration for all machines.
  baselineSupportedFeatures = [
    "benchmark"
    "big-parallel"
    "ca-derivations"
    "kvm"
    "nixos-test"
    "recursive-nix"
  ];

  # Maps host names to machine architecture.
  # NOTE: Hard-coding this here allows us avoiding evaluating multiple system closures
  # to get their configurations.
  # hostNameToSystem :: AttrSet String (AttrSet String Any)
  hostNameToBuildMachineConfig =
    let
      mkBuildMachineConfig = hostName: machine: {
        hostName =
          if config.programs.nix-grpc-store.enable then
            "grpc://${hostName}.rove-hexatonic.ts.net:50051?insecure=1&connect-timeout=5"
          else
            hostName + "?max-connections=1&want-mass-query=true";
        supportedFeatures = baselineSupportedFeatures ++ machine.features;
        maxJobs = 3;
        # Ext schedules CPU jobs through Tribuchet. Direct gRPC builders
        # serve GPU jobs, which Tribuchet workers cannot advertise.
        mandatoryFeatures = lib.optionals (builtins.elem "cuda" machine.features) [ "cuda" ];
        protocol = if config.programs.nix-grpc-store.enable then null else "ssh-ng";
        speedFactor = 1;
        sshKey =
          if config.programs.nix-grpc-store.enable then null else config.sops.secrets.${nixPrivateKey}.path;
        inherit (machine) systems;
      };
    in
    mapAttrs mkBuildMachineConfig {
      nixos-build01 = {
        systems = [ "x86_64-linux" ];
        features = [ ];
      };
      nixos-desktop = {
        systems = [ "x86_64-linux" ];
        features = [ "cuda" ];
      };
      # Ext's external builder routes both architectures through its pool.
      nixos-ext = {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        features = [ "uid-range" ];
      };
      nixos-orin = {
        systems = [ "aarch64-linux" ];
        features = [ "cuda" ];
      };
    };
in
{
  imports = [ ../services/tribuchet.nix ];
  _module.args.patchedNix = patchedNix;
  networking.hosts = {
    "192.168.1.12" = [ "nixos-desktop" ];
    "192.168.1.13" = [ "nixos-ext" ];
    "192.168.1.14" = [ "nixos-build01" ];
  };

  nix = {
    # Use flakes for everything
    channel.enable = false;

    # The hub module selects this same package through externalBuilders.
    package = lib.mkDefault patchedNix;

    buildMachines = attrValues (
      lib.filterAttrs (
        hostName: machine:
        hostName != config.networking.hostName
        && (hostName == "nixos-ext" || builtins.elem "cuda" machine.supportedFeatures)
      ) hostNameToBuildMachineConfig
    );

    distributedBuilds = true;

    settings = {
      auto-optimise-store = false; # Do it manually or on a schedule to avoid a slowdown per-build.
      builders-use-substitutes = true;
      connect-timeout = 5; # Don't wait forever for a remote builder to respond.
      # Since these machines are builders for CUDA packages, makes sense to allow a larger buffer for curl because we
      # have lots of memory and will be downloading large tarballs.
      # NOTE: https://github.com/NixOS/nix/pull/11171
      download-buffer-size = 256 * 1024 * 1024; # 256 MB
      experimental-features = [
        "ca-derivations"
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
      # See: https://github.com/NixOS/nix/blob/1cd48008f0e31b0d48ad745b69256d881201e5ee/src/libstore/local-store.cc#L1172
      nar-buffer-size = 1 * 1024 * 1024 * 1024; # 1 GB
      require-drop-supplementary-groups = true;
      system-features =
        hostNameToBuildMachineConfig.${config.networking.hostName}.supportedFeatures
          or baselineSupportedFeatures;
      trusted-users = [
        "root"
        "@nixbld"
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
    '') (attrNames hostNameToBuildMachineConfig);
    knownHosts = genAttrs (attrNames hostNameToBuildMachineConfig) (hostName: {
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
