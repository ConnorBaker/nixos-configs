{ lib, modulesPath, ... }:
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "usbhid"
      "xhci_pci"
    ];
    kernelModules = [ "kvm-amd" ];
    kernelParams = [ "amd_pstate=active" ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  nixpkgs = {
    config = {
      allowUnfree = lib.modules.mkForce true;
      cudaSupport = lib.modules.mkForce true;
      cudaCapabilities = lib.modules.mkForce [ "8.9" ];
    };
    hostPlatform.system = "x86_64-linux";
  };
}
