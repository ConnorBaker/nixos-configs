{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Common configuration for all machines.
  # Maps host names to machine architecture.
  # hostNameToSystem :: AttrSet String (AttrSet String Any)
  hostNameToConfig = {
    nixos-build01 = { };
    nixos-desktop = { };
    nixos-ext = { };
    ubuntu-orin = {
      maxJobs = 8;
      speedFactor = 1;
      systems = [ "aarch64-linux" ];
    };
    ubuntu-hetzner = {
      maxJobs = 40;
      speedFactor = 16;
      systems = [ "aarch64-linux" ];
    };
  };
  supportedFeatures = [
    "benchmark"
    "big-parallel"
    "ca-derivations"
    "kvm"
    "nixos-test"
    "uid-range"
  ];
  # Functions to generate machine-specific configuration.
  # Attributes defined in the hostNameToConfig map override these defaults.
  # machineBoilerplate :: String -> AttrSet String Any -> AttrSet String Any
  machineBoilerplate =
    hostName:
    lib.attrsets.recursiveUpdate {
      inherit hostName supportedFeatures;
      maxJobs = 32;
      protocol = "ssh-ng";
      speedFactor = 8;
      sshKey = "/etc/ssh/id_nix_ed25519";
      sshUser = "nix";
      systems = [ "x86_64-linux" ];
    };
  # A machine should not have itself as a remote builder.
  irreflexive = hostName: _: hostName != config.networking.hostName;
in
{
  imports = [ ./secrets.nix ];

  # Must manually add ubuntu-hetzner because it is not in my Tailscale network.
  networking.hosts = {
    "65.21.10.91" = [ "ubuntu-hetzner" ];
    "2a01:4f9:3080:40c1::2" = [ "ubuntu-hetzner" ];
    "192.168.1.204" = [ "ubuntu-orin" ];
  };

  nix = {
    # Choose the version of Nix to use.
    package = pkgs.nixVersions.latest;

    buildMachines = lib.trivial.pipe hostNameToConfig [
      # AttrSet String (AttrSet String Any) -> AttrSet String (AttrSet String Any)
      (lib.attrsets.filterAttrs irreflexive)
      # AttrSet String (AttrSet String Any) -> AttrSet String (AttrSet String Any)
      (lib.attrsets.mapAttrs machineBoilerplate)
      # AttrSet String (AttrSet String Any) -> List (AttrSet String Any)
      lib.attrsets.attrValues
    ];
    distributedBuilds = true;
    settings = {
      accept-flake-config = true;
      allow-import-from-derivation = false;
      auto-allocate-uids = true;
      auto-optimise-store = true;
      builders-use-substitutes = true;
      connect-timeout = 30;
      experimental-features = [
        "auto-allocate-uids"
        "ca-derivations"
        "cgroups"
        "configurable-impure-env"
        "dynamic-derivations"
        "fetch-closure"
        "fetch-tree"
        "flakes"
        "git-hashing"
        "mounted-ssh-store"
        "nix-command"
        "no-url-literals"
        "parse-toml-timestamps"
        "recursive-nix"
        "verified-fetches"
      ];
      extra-substituters = [
        "https://cache.ngi0.nixos.org"
        "https://cuda-maintainers.cachix.org"
      ];
      extra-trusted-substituters = [
        "https://cache.ngi0.nixos.org"
        "https://cuda-maintainers.cachix.org"
      ];
      extra-trusted-public-keys = [
        "cache.ngi0.nixos.org-1:KqH5CBLNSyX184S9BKZJo1LxrxJ9ltnY2uAs5c/f1MA="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      ];
      fsync-metadata = false;
      http-connections = 256;
      max-substitution-jobs = 128;
      require-drop-supplementary-groups = true;
      system-features = supportedFeatures;
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

  programs.ssh.knownHosts = lib.attrsets.genAttrs (builtins.attrNames hostNameToConfig) (hostName: {
    publicKeyFile = ../.. + "/devices/${hostName}/keys/ssh_host_ed25519_key.pub";
  });

  users.users = {
    nix = {
      description = "Nix account";
      extraGroups = [ "wheel" ];
      isNormalUser = true;
      openssh.authorizedKeys.keyFiles = [ ./keys/id_nix_ed25519.pub ];
    };
    root.openssh.authorizedKeys.keyFiles = [ ./keys/id_nix_ed25519.pub ];
  };
}
