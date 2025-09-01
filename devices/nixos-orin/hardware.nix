{ lib, modulesPath, ... }:
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  hardware = {
    # TODO: graphics.enable shouldn't need to be set by us; it should happen through jetpack nixos.
    graphics.enable = true;
    nvidia-jetpack = {
      enable = true;
      maxClock = true;
      som = "orin-agx";
      carrierBoard = "devkit";
    };
  };

  networking = {
    useNetworkd = true;
    wireless.iwd.enable = true;
  };


  systemd.network.networks."10-ethernet" = {
    linkConfig.MACAddress = "48:b0:2d:e7:6e:20";
    networkConfig = {
      DHCP = lib.mkForce "yes";
      # NOTE: Requires accurate time, which I don't have yet across power loss without an RTC battery.
      DNSOverTLS = lib.mkForce false;
    };
  };
}
