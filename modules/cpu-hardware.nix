{
  hardware = {
    cpu = {
      amd.updateMicrocode = true;
      intel.updateMicrocode = true;
    };
    enableAllFirmware = true;
  };
  nixpkgs.config.allowUnfree = true;
  powerManagement.cpuFreqGovernor = "performance";
}
