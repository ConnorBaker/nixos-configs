{ config, ... }:
{
  hardware = {
    graphics.enable = true;
    nvidia = {
      nvidiaPersistenced = false;
      package = config.boot.kernelPackages.nvidiaPackages.beta;
      powerManagement.enable = true;
    };
  };
  nixpkgs.config = {
    allowUnfree = true;
    cudaSupport = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ];
}
