{config, lib, ...}:
let
  # Common configuration for all machines.
  # Maps host names to machine architecture.
  # hostNameToSystem :: AttrSet String (AttrSet String Any)
  hostNameToConfig = {
    nixos-build01 = {
      speedFactor = 8;
      systems = ["x86_64-linux"];
    };
    nixos-desktop = {
      speedFactor = 8;
      systems = ["x86_64-linux"];
    };
    nixos-ext = {
      speedFactor = 8;
      systems = ["x86_64-linux"];
    };
    ubuntu-orin = {
      speedFactor = 1;
      systems = ["aarch64-linux"];
    };
    ubuntu-hetzner = {
      maxJobs = 40;
      speedFactor = 16;
      systems = ["aarch64-linux"];
    };
  };
  maxJobs = 1;
  supportedFeatures = [
    "benchmark"
    "big-parallel"
    "kvm"
    "nixos-test"
  ];
  # Functions to generate machine-specific configuration.
  # Attributes defined in the hostNameToConfig map override these defaults.
  # machineBoilerplate :: String -> AttrSet String Any -> AttrSet String Any
  machineBoilerplate =
    hostName:
    lib.attrsets.recursiveUpdate {
      inherit hostName maxJobs supportedFeatures;
      protocol = "ssh-ng";
      sshKey = "/etc/ssh/id_nix_ed25519";
      sshUser = "nix";
    };
  # A machine should not have itself as a remote builder.
  irreflexive = hostName: _: hostName != config.networking.hostName;
in
{
  imports = [./secrets.nix];

  # Must manually add ubuntu-hetzner because it is not in my Tailscale network.
  networking.hosts = {
    "65.21.10.91" = ["ubuntu-hetzner"];
    "2a01:4f9:3080:40c1::2" = ["ubuntu-hetzner"];
    "192.168.1.204" = ["ubuntu-orin"];
  };

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
      allow-import-from-derivation = false;
      auto-allocate-uids = true;
      auto-optimise-store = true;
      builders-use-substitutes = true;
      connect-timeout = 30;
      cores = 0;
      experimental-features = [
        "auto-allocate-uids"
        "ca-derivations"
        "cgroups"
        "flakes"
        # "git-hashing"
        "nix-command"
        "no-url-literals"
      ];
      extra-substituters = ["https://cuda-maintainers.cachix.org"];
      extra-trusted-substituters = ["https://cuda-maintainers.cachix.org"];
      extra-trusted-public-keys = [
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      ];
      fsync-metadata = false;
      http-connections = 0;
      keep-derivations = true;
      keep-outputs = true;
      max-jobs = maxJobs;
      max-substitution-jobs = 256;
      narinfo-cache-negative-ttl = 0;
      require-drop-supplementary-groups = true;
      system-features = supportedFeatures;
      trusted-users = [
        "root"
        "@nixbld"
        "@wheel"
      ];
      use-cgroups = true;
      use-xdg-base-directories = true;
    };
  };

  programs.ssh.knownHosts = lib.attrsets.genAttrs (builtins.attrNames hostNameToConfig) (
    hostName: {publicKeyFile = ../.. + "/devices/${hostName}/keys/ssh_host_ed25519_key.pub";}
  );

  users.users = {
    nix = {
      description = "Nix account";
      extraGroups = ["wheel"];
      isNormalUser = true;
      openssh.authorizedKeys.keyFiles = [./keys/id_nix_ed25519.pub];
    };
    root.openssh.authorizedKeys.keyFiles = [./keys/id_nix_ed25519.pub];
  };
}
