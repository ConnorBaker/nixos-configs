{
  config,
  lib,
  ...
}: {
  imports = [
    ./ext4.nix
    ./hardware.nix

    # Configure Nix
    ../../modules/nix/nix.nix

    # Configure system
    ../../modules/boot.nix
    ../../modules/cpu-hardware.nix
    # ../../modules/networking.nix
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

  networking = {
    hostName = "hetzner-ext";
    useDHCP = false;
    useNetworkd = true;
    dhcpcd.enable = false;
  };
  services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
  users.users.root.openssh.authorizedKeys = {
    inherit (config.users.users.connorbaker.openssh.authorizedKeys) keys;
  };
  systemd.network = {
    enable = true;
    wait-online = {
      anyInterface = true;
      timeout = 30;
    };
    networks."20-wired" = {
      matchConfig = {
        Name = "eno* eth*";
        MACAddress = "24:4b:fe:b8:5f:d9";
      };
      networkConfig = {
        Address = ["2a01:4f9:6a:1692::2/64"];
        Gateway = ["fe80::1"];
        DHCP = "yes";
        DNSSEC = "allow-downgrade";
        DNSOverTLS = "opportunistic";
        DNS = [
          # Kasper Dupont's Public NAT64 service: https://nat64.net
          "2a01:4f9:c010:3f02::1"
          "2a00:1098:2c::1"
          "2a00:1098:2b::1"
        ];
      };
      # TODO(@connorbaker): DHCP static leases?
      # https://github.com/NixOS/nixpkgs/blob/96d403ee2479f2070050353b94808209f1352edb/nixos/tests/systemd-networkd-dhcpserver-static-leases.nix#L30-L35
    };
  };
  system.stateVersion = "23.05";
}
