{ config, ... }:
{
  hardware = {
    nvidia = {
      nvidiaPersistenced = false;
      package = config.boot.kernelPackages.nvidiaPackages.beta;
      powerManagement.enable = true;
    };
    opengl.enable = true;
  };
  nixpkgs.config = {
    allowUnfree = true;
    cudaSupport = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ];
}
