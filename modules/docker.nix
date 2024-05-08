{ pkgs, ... }:
{
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation = {
    containers.enable = true;
    docker = {
      enable = true;
      # CDI is feature-gated and only available from Docker 25 and onwards
      package = pkgs.docker_25;
      daemon.settings.features.cdi = true;
    };
    oci-containers.backend = "docker";
  };
}
