{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "usbhid"
      "xhci_pci"
    ];
    kernelModules = [ "kvm-amd" ];
    kernelParams = [ "amd_pstate=active" ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  hardware = {
    cpu.amd.updateMicrocode = true;
    enableAllFirmware = true;
  };

  powerManagement.cpuFreqGovernor = "performance";

  systemd.network.networks."10-ether" =
    let
      cfg = config.systemd.network.networks."10-ether";
    in
    {
      linkConfig.MACAddress = "e8:9c:25:5e:3c:6d";

      networkConfig = {
        Address = "192.168.1.13/24";
        Gateway = "192.168.1.1";
        DHCP = lib.mkForce "ipv6";
      };

      # IPv4 Static Leases
      dhcpServerStaticLeases = [
        {
          inherit (cfg.linkConfig) MACAddress;
          Address = lib.removeSuffix "/24" cfg.networkConfig.Address;
        }
      ];

      routes = lib.mkBefore [
        {
          inherit (cfg.networkConfig) Gateway;
          GatewayOnLink = true;
        }
        { Destination = cfg.networkConfig.Gateway; }
      ];
    };
}
