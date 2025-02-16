{ modulesPath, ... }:
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

  systemd.network.networks."10-ethernet" = {
    linkConfig.MACAddress = "e8:9c:25:5e:3c:6d";
    networkConfig = {
      Address = "192.168.1.13/24";
      Gateway = "192.168.1.1";
    };
  };
}
