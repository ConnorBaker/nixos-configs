{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  # srvos has a wealth of information about how to configure Hetzner machines.
  # https://github.com/nix-community/srvos/blob/5d4550de420ee501d7fa0e6cd9031cd00354554c/nixos/hardware/hetzner-online/default.nix
  boot = {
    initrd = {
      availableKernelModules = [
        "ahci"
        "nvme"
        "usbhid"
        "xhci_pci"
      ];
      # Network configuration i.e. when we unlock machines with openssh in the initrd
      systemd.network.networks."10-ethernet" = config.systemd.network.networks."10-ethernet";
    };
    kernelModules = [ "kvm-amd" ];
    kernelParams = [ "amd_pstate=active" ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  nixpkgs = {
    config.allowUnfree = lib.modules.mkForce true;
    hostPlatform.system = "x86_64-linux";
  };

  systemd.network.networks."10-ethernet" = {
    extraConfig = lib.modules.mkForce "";
    networkConfig = {
      DHCP = lib.modules.mkForce false;
      IPv6AcceptRA = false;
    };
    addresses = [
      { addressConfig.Address = "65.109.152.76/32"; }
      { addressConfig.Address = "2a01:4f9:3080:5652::2/64"; }
    ];
    routes = [
      { routeConfig.Destination = "65.109.152.1"; }
      {
        routeConfig = {
          Gateway = "65.109.152.1";
          GatewayOnLink = true;
        };
      }
      { routeConfig.Gateway = "fe80::1"; }
    ];
  };
}
