{ config, lib, ... }:
{
  hardware.nvidia-container-toolkit.enable = lib.lists.elem "nvidia" config.services.xserver.videoDrivers;
  virtualisation = {
    containers.enable = true;
    docker = {
      enable = true;
      daemon.settings.features.cdi = true;
    };
    oci-containers.backend = "docker";
  };
}
