{modulesPath, ...}: {
  imports = ["${modulesPath}/installer/scan/not-detected.nix"];

  boot = {
    initrd = {
      availableKernelModules = [
        "ahci"
        "nvme"
        "thunderbolt"
        "vmd"
        "xhci_pci"
      ];
      kernelModules = ["dm-snapshot"];
    };
    kernelModules = ["kvm-intel"];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
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

  nixpkgs.hostPlatform = "x86_64-linux";
  powerManagement.cpuFreqGovernor = "powersave";
}
