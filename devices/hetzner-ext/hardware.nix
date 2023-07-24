{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/installer/scan/not-detected.nix"];

  boot = {
    initrd.availableKernelModules = [
      # TODO(@connorbaker): These are mostly copied from the desktop.
      "ahci"
      "sd_mod"
      "uas"
      "vmd"
    ];
    kernelModules = ["btrfs" "kvm-intel"];
  };

  fileSystems = {
    "/".device = "/dev/disk/by-partlabel/disk-main-nixos";
    "/boot".device = "/dev/disk/by-partlabel/disk-main-ESP";
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  swapDevices = [];
}
