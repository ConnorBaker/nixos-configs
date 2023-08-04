{modulesPath, ...}: {
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
    loader.systemd-boot.enable = true;
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  powerManagement.cpuFreqGovernor = "powersave";
}
