{
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "thunderbolt"
      "vmd"
      "xhci_pci"
    ];
    kernelModules = [ "kvm-intel" ];
    kernelParams = [ "intel_pstate=active" ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  hardware = {
    cpu.intel.updateMicrocode = true;
    enableAllFirmware = true;
    graphics.enable = true;
    nvidia = {
      open = true;
      branch = "latest";
      moduleParams.nvidia.NVreg_RestrictProfilingToAdminUsers = 0;
      powerManagement.enable = true;
    };
  };

  powerManagement = {
    cpuFreqGovernor = "performance";
    # The i9-13900K's 5.8 GHz boost cores (CPUs 4-7) segfault under load:
    # ghc, z3 and libc crashes all landed on CPUs 4-5. Capping every core
    # at 5.2 GHz stops them. The cpufreq unit applies this at boot.
    cpufreq.max = 5200000;
  };

  programs.nix-required-mounts = {
    enable = true;
    presets.nvidia-gpu.enable = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

}
