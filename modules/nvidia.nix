{ config, pkgs, ... }:
{
  assertions = [
    {
      assertion = pkgs.config.allowUnfree;
      message = "Unfree packages must be allowed";
    }
    {
      assertion = pkgs.config.cudaSupport;
      message = "CUDA support must be enabled";
    }
  ];
  hardware = {
    graphics.enable = true;
    nvidia = {
      nvidiaPersistenced = false;
      open = true;
      package = config.boot.kernelPackages.nvidiaPackages.latest;
      powerManagement.enable = true;
    };
  };
  services.xserver.videoDrivers = [ "nvidia" ];
}
