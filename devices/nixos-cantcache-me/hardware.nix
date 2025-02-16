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

  systemd.network.networks."10-ethernet" =
    let
      # When we have multiple addresses, we need to configure a bit more manually.
      Address = "65.109.152.76/24";
      Gateway = "65.109.152.1";
      AddressV6 = "2a01:4f9:3080:5652::2/64";
      GatewayV6 = "fe80::1";
    in
    {
      # Normal networking settings
      linkConfig.MACAddress = "90:e2:ba:ec:42:a2";
      networkConfig = {
        inherit Address Gateway;
      };

      # Hetzner-specific settings
      networkConfig = {
        DHCP = lib.modules.mkForce false;
        IPv6AcceptRA = false;
      };
      addresses = [
        { inherit Address; }
        { Address = AddressV6; }
      ];
      routes = [ { Gateway = GatewayV6; } ];
    };
}
