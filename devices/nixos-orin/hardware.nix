{ modulesPath, ... }:
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  hardware.nvidia-jetpack = {
    enable = true;
    som = "orin-agx";
    carrierBoard = "devkit";
  };

  systemd.network.networks."10-ethernet" = {
    linkConfig.MACAddress = "48:b0:2d:e7:6e:20";
    networkConfig = {
      Address = "192.168.1.17/24";
      Gateway = "192.168.1.1";
    };
  };
}
