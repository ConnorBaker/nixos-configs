{modulesPath, ...}: {
  imports = ["${modulesPath}/installer/scan/not-detected.nix"];

  boot = {
    binfmt.emulatedSystems = ["aarch64-linux"];
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "thunderbolt"
      "usbhid"
      "xhci_pci"
    ];
    kernelModules = ["kvm-amd"];
    kernelParams = ["amd_pstate=active"];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  nixpkgs.hostPlatform.system = "x86_64-linux";
}
