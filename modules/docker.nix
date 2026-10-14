{ config, lib, ... }:
{
  hardware.nvidia-container-toolkit.enable = lib.lists.elem "nvidia" config.services.xserver.videoDrivers;
  virtualisation = {
    docker = {
      enable = true;
    };
    oci-containers.backend = "docker";
  };
}
