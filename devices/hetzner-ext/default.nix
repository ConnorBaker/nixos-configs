{
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko

    # ZFS-relevant changes to boot, networking, services, etc.
    ./zfs.nix

    # Changes for impermanence
    ./impermanence.nix

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

    # Users
    ../../users/connorbaker.nix
  ];

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };

  networking = {
    hostName = "hetzner-ext";
    useDHCP = false;
    useNetworkd = true;
  };

  system.stateVersion = "23.05";

  systemd.network = {
    enable = true;
    networks."10-eno1" = {
      address = ["2a01:4f9:6a:1692::2/64"];
      DHCP = "no";
      dns = ["2a01:4f9:c010:3f02::1"];
      gateway = ["fe80::1"];
      name = "eno1";
      networkConfig = {
        LLMNR = false;
        DNSOverTLS = "opportunistic";
        DNSSEC = "allow-downgrade";
      };
    };
    wait-online.anyInterface = true;
  };
}
