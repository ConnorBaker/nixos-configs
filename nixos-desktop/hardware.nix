{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/installer/scan/not-detected.nix"];

  boot = {
    initrd = {
      availableKernelModules = [
        "ahci"
        "nvme"
        "sd_mod"
        "thunderbolt"
        "uas"
        "usbhid"
        "vmd"
        "xhci_pci"
      ];
      kernelModules = ["dm-snapshot"];
    };
    kernelModules = ["kvm-intel"];
    extraModulePackages = [];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/40a18657-ebc2-4eec-a26d-b03e0beb261f";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/B581-C944";
      fsType = "vfat";
    };
  };

  swapDevices = [];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
