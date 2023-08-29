{modulesPath, ...}: {
  imports = ["${modulesPath}/installer/scan/not-detected.nix"];

  boot = {
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

  nixpkgs = {
    # config.replaceStdenv = {pkgs, ...}: pkgs.fastStdenv;
    hostPlatform = {
      gcc = {
        # TODO(@connorbaker): Zen 5 is too new
        arch = "znver4";
        tune = "znver4";
      };
      system = "x86_64-linux";
    };
  };
}
