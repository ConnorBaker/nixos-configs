{
  lib,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/installer/scan/not-detected.nix"];

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "sd_mod"
      "thunderbolt"
      "uas"
      "usbhid"
      "xhci_pci"
    ];
    kernelModules = ["kvm-amd"];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
}
