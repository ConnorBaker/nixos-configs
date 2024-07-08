{ lib, modulesPath, ... }:
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "thunderbolt"
      "vmd"
      "xhci_pci"
    ];
    kernelModules = [ "kvm-intel" ];
    kernelParams = [ "intel_pstate=active" ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  nixpkgs = {
    config = {
      allowUnfree = lib.modules.mkForce true;
      cudaSupport = lib.modules.mkForce true;
      cudaCapabilities = lib.modules.mkForce [ "8.9" ];
    };
    hostPlatform.system = "x86_64-linux";
  };

  systemd.network.networks."10-ethernet" = {
    linkConfig.MACAddress = "58:11:22:b4:9d:69";
    networkConfig = {
      Address = "192.168.1.12";
      Gateway = "192.168.1.1";
    };
  };
}
