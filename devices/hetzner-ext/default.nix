{
  imports = [
    ./hardware.nix

    # Disko
    ./disks.nix

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

  # boot.loader = {
  #   grub = {
  #     copyKernels = true;
  #     devices = ["/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2AE5N5"];
  #     efiInstallAsRemovable = true;
  #     efiSupport = true;
  #     enable = true;
  #     fsIdentifier = "uuid";
  #     version = 2;
  #   };
  #   systemd-boot.enable = false;
  # };

  networking = {
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
    firewall.logRefusedConnections = false;
    hostName = "hetzner-ext";
    interfaces."eth0".ipv6.addresses = [
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
    # Network (Hetzner uses static IP assignments, and we don't use DHCP here)
    useDHCP = false;
  };
  system.stateVersion = "23.05";
}
