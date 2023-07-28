{
  config,
  lib,
  ...
}: {
  imports = [
    ./disks.nix
    ./hardware.nix

    # Configure Nix
    ../../modules/nix/nix.nix

    # Configure system
    ../../modules/boot.nix
    ../../modules/cpu-hardware.nix
    ../../modules/networking.nix
    ../../modules/headless.nix
    ../../modules/users.nix
    ../../modules/mimalloc.nix
    ../../modules/zram.nix
    ../../modules/sudo.nix

    # Configure services
    ../../modules/services/openssh.nix

    # Configure programs
    ../../modules/programs/git.nix
    ../../modules/programs/htop.nix
    ../../modules/programs/nix-ld.nix

    # Users
    ../../users/connorbaker.nix
  ];

  # TODO(@connorbaker): Freezes when using ZFS?
  # https://github.com/numtide/srvos/blob/ce0426c357c077edec3aacde8e9649f30f1be659/nixos/common/zfs.nix#L13-L16
  boot = {
    initrd.supportedFilesystems = ["zfs"];
    kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
    kernelParams = ["nohibernate"];
    loader.grub = {
      copyKernels = true;
      efiSupport = false;
      enable = true;
    };
    supportedFilesystems = ["zfs"];
    zfs.forceImportRoot = false;
  };

  networking = {
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
    firewall.logRefusedConnections = false;
    hostId = "00000000";
    hostName = "hetzner-ext";
    interfaces.eth0.ipv6.addresses = [
      {
        address = "2a01:4f8:10a:eae::2";
        prefixLength = 64;
      }
    ];
    nameservers = [
      # Kasper Dupont's Public NAT64 service: https://nat64.net
      "2a01:4f9:c010:3f02::1"
      "2a00:1098:2c::1"
      "2a00:1098:2b::1"
    ];
    networkmanager.enable = false;
    useNetworkd = false;
    # Network (Hetzner uses static IP assignments, and we don't use DHCP here)
    useDHCP = false;
  };
  services = {
    openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };
  };
  users.users.root.openssh.authorizedKeys = {
    inherit (config.users.users.connorbaker.openssh.authorizedKeys) keys;
  };
  system.stateVersion = "23.05";
}
