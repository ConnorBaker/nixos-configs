{ pkgs, ... }:
{
  virtualisation = {
    containers = {
      enable = true;
      cdi.dynamic.nvidia.enable = true;
    };
    docker = {
      enable = true;
      # CDI is feature-gated and only available from Docker 25 and onwards
      package = pkgs.docker_25;
      daemon.settings.features.cdi = true;
      storageDriver = "zfs";
    };
    oci-containers.backend = "docker";
  };
}
