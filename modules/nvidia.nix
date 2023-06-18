{config, ...}: {
  environment.noXlibs = false;
  hardware = {
    nvidia = {
      nvidiaPersistenced = true;
      package = config.boot.kernelPackages.nvidiaPackages.latest;
    };
    opengl.enable = true;
  };
  nixpkgs = {
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  };
  services.xserver.videoDrivers = ["nvidia"];
}
