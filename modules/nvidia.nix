{ config, ... }:
{
  hardware = {
    graphics.enable = true;
    nvidia = {
      nvidiaPersistenced = false;
      open = true;
      package = config.boot.kernelPackages.nvidiaPackages.latest;
      powerManagement.enable = true;
    };
  };
  nixpkgs.config = {
    allowUnfree = true;
    cudaSupport = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ];
}
