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
      device = "/dev/disk/by-partlabel/disk-main-root";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-partlabel/disk-main-boot";
      fsType = "vfat";
    };
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  swapDevices = [];
}
