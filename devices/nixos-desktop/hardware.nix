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

  # The board sets the package's long-term power limit (PL1) to 253 W, the same
  # as its short-term limit; Intel rates the i9-13900K at 125 W base power and
  # 253 W maximum turbo power. Even with the 5.2 GHz cap the package reaches
  # 100 °C and throttles under ordinary load, and the cooling cannot be changed
  # remotely. Hold PL1 at Intel's 125 W and leave PL2 as the board sets it.
  systemd.services.rapl-long-term-limit = {
    description = "Hold the CPU package's long-term power limit at 125 W";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    unitConfig.ConditionPathExists = "/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      rapl=/sys/class/powercap/intel-rapl:0
      name=$(cat "$rapl/name") constraint=$(cat "$rapl/constraint_0_name")
      if [ "$name" != package-0 ] || [ "$constraint" != long_term ]; then
        echo "expected package-0/long_term at $rapl, found $name/$constraint" >&2
        exit 1
      fi
      echo 125000000 > "$rapl/constraint_0_power_limit_uw"
    '';
  };

  programs.nix-required-mounts = {
    enable = true;
    presets.nvidia-gpu.enable = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

}
