{
  lib,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/installer/scan/not-detected.nix"];

  boot = {
    binfmt.emulatedSystems = ["aarch64-linux"];
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "thunderbolt"
      "vmd"
      "xhci_pci"
    ];
    kernelModules = ["kvm-intel"];
    kernelParams = ["intel_pstate=active"];
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

  nixpkgs = lib.modules.mkForce {
    config = {
      allowUnfree = true;
      cudaSupport = true;
      cudaCapabilities = ["8.9"];
    };
    hostPlatform.system = "x86_64-linux";
  };
}
