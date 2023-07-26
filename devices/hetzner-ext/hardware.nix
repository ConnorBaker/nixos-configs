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
    kernelModules = ["kvm-intel"];
  };

  # NOTE: Disko takes care of the filesystem for us; no need to specify boot or root.

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  swapDevices = [];
}
