{
  config,
  lib,
  pkgs,
  ...
}:
{
  hardware.nvidia-container-toolkit.enable = lib.lists.elem "nvidia" config.services.xserver.videoDrivers;
  virtualisation = {
    containers.enable = true;
    docker = {
      enable = true;
      # CDI is feature-gated and only available from Docker 25 and onwards, which is not yet the default.
      package =
        let
          package = pkgs.docker_25;
          defaultPackage = pkgs.docker;
          pinnedIsAtLeastAsRecentAsDefault = lib.versionAtLeast package.version defaultPackage.version;
        in
        assert lib.asserts.assertMsg pinnedIsAtLeastAsRecentAsDefault ''
          "The default version of docker (${defaultPackage.version}) is now newer than the pinned version
          (${package.version}). Please update to use the default version.
        '';
        package;
      daemon.settings.features.cdi = true;
    };
    oci-containers.backend = "docker";
  };
}
