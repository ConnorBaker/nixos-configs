{modulesPath, ...}: {
  imports = ["${modulesPath}/installer/scan/not-detected.nix"];

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "sd_mod"
      "xhci_pci"
    ];
    kernelModules = ["kvm-intel"];
    loader.grub = {
      copyKernels = true;
      enable = true;
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  powerManagement.cpuFreqGovernor = "powersave";
}
