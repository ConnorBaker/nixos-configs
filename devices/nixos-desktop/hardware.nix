{modulesPath, ...}: {
  imports = ["${modulesPath}/installer/scan/not-detected.nix"];

  boot = {
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

  # TODO: Not being picked up by the actual build because this is what the resulting OS would use, not what we use to build the OS.
  nixpkgs = {
    # config.replaceStdenv = {pkgs, ...}: pkgs.fastStdenv;
    hostPlatform = {
      gcc = {
        # TODO(@connorbaker): Raptor Lake is too new
        arch = "alderlake";
        tune = "alderlake";
      };
      system = "x86_64-linux";
    };
  };
}
