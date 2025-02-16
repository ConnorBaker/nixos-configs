{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.attrsets)
    attrNames
    attrValues
    filterAttrs
    genAttrs
    mapAttrs
    recursiveUpdate
    ;
  inherit (lib.strings) concatMapStringsSep;
  inherit (lib.trivial) pipe;

  nixPrivateKey = "ssh/id_nix_ed25519";

  # Common configuration for all machines.
  baselineSupportedFeatures = [
    "benchmark"
    "big-parallel"
    "ca-derivations"
    "kvm"
    "nixos-test"
    "uid-range"
  ];
  # Maps host names to machine architecture.
  # hostNameToSystem :: AttrSet String (AttrSet String Any)
  hostNameToConfig = {
    nixos-build01 = { };
    nixos-desktop.supportedFeatures = baselineSupportedFeatures ++ [ "cuda" ];
    nixos-ext = { };
    # "eu.nixbuild.net" = {
    #   maxJobs = 100;
    #   speedFactor = 32;
    #   supportedFeatures = [
    #     "benchmark"
    #     "big-parallel"
    #   ];
    #   systems = [
    #     "aarch64-linux"
    #     "x86_64-linux"
    #   ];
    # };
    # ubuntu-orin = {
    #   maxJobs = 8;
    #   speedFactor = 1;
    #   systems = [ "aarch64-linux" ];
    # };
    # ubuntu-hetzner = {
    #   maxJobs = 40;
    #   speedFactor = 16;
    #   systems = [ "aarch64-linux" ];
    # };
  };
  # Functions to generate machine-specific configuration.
  # Attributes defined in the hostNameToConfig map override these defaults.
  # machineBoilerplate :: String -> AttrSet String Any -> AttrSet String Any
  machineBoilerplate =
    hostName:
    recursiveUpdate {
      inherit hostName;
      supportedFeatures = baselineSupportedFeatures;
      maxJobs = 2;
      protocol = "ssh-ng";
      speedFactor = 8;
      sshKey = config.sops.secrets.${nixPrivateKey}.path;
      systems = [ "x86_64-linux" ];
    };
in
{
  # Must manually add ubuntu-hetzner because it is not in my Tailscale network and so DNS resolution fails.
  networking.hosts = {
    "65.21.10.91" = [ "ubuntu-hetzner" ];
    "2a01:4f9:3080:40c1::2" = [ "ubuntu-hetzner" ];
    "192.168.1.12" = [ "nixos-desktop" ];
    "192.168.1.13" = [ "nixos-ext" ];
    "192.168.1.14" = [ "nixos-build01" ];
    "192.168.1.204" = [ "ubuntu-orin" ];
  };

  nix = {
    # Choose the version of Nix to use.
    package = pkgs.nixVersions.latest;

    buildMachines = pipe hostNameToConfig [
      # AttrSet String (AttrSet String Any) -> AttrSet String (AttrSet String Any)
      # A machine should not have itself as a remote builder.
      (filterAttrs (hostName: _: hostName != config.networking.hostName))
      # AttrSet String (AttrSet String Any) -> AttrSet String (AttrSet String Any)
      (mapAttrs machineBoilerplate)
      # AttrSet String (AttrSet String Any) -> List (AttrSet String Any)
      attrValues
    ];
    distributedBuilds = true;
    settings = {
      accept-flake-config = true;
      auto-allocate-uids = true;
      auto-optimise-store = false; # We wipe them frequently enough we don't need the performance hit.
      builders-use-substitutes = true;
      connect-timeout = 5; # Don't wait forever for a remote builder to respond.
      # Since these machines are builders for CUDA packages, makes sense to allow a larger buffer for curl because we
      # have lots of memory and will be downloading large tarballs.
      # NOTE: https://github.com/NixOS/nix/pull/11171
      download-buffer-size = 256 * 1024 * 1024; # 256 MB
      experimental-features = [
        "auto-allocate-uids"
        "ca-derivations"
        "cgroups"
        "dynamic-derivations"
        "flakes"
        "impure-derivations"
        "nix-command"
      ];
      fallback = true;
      fsync-metadata = false;
      http-connections = 32;
      log-lines = 100;
      max-jobs = 2;
      max-substitution-jobs = 32;
      # See: https://github.com/NixOS/nix/blob/1cd48008f0e31b0d48ad745b69256d881201e5ee/src/libstore/local-store.cc#L1172
      nar-buffer-size = 1 * 1024 * 1024 * 1024; # 1 GB
      require-drop-supplementary-groups = true;
      system-features =
        hostNameToConfig.${config.networking.hostName}.supportedFeatures or baselineSupportedFeatures;
      trusted-users = [
        "root"
        "@nixbld"
        "@wheel"
      ];
      use-cgroups = true;
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
    '') (attrNames hostNameToConfig);
    knownHosts = genAttrs (attrNames hostNameToConfig) (hostName: {
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
