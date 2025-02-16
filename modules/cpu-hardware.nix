{ pkgs, ... }:
{
  assertions = [
    {
      assertion = pkgs.config.allowUnfree;
      message = "Unfree packages must be allowed";
    }
  ];
  hardware = {
    cpu = {
      amd.updateMicrocode = true;
      intel.updateMicrocode = true;
    };
    enableAllFirmware = true;
  };
  powerManagement.cpuFreqGovernor = "performance";
}
