{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  boot = {
    kernelPatches = [
      {
        name = "gadget-mode";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          USB_CDC_COMPOSITE = module;
          USB_G_ACM_MS = module;
          USB_G_DBGP = module;
          USB_G_HID = module;
          USB_G_MULTI = module;
          USB_G_MULTI_CDC = yes;
          USB_G_NCM = module;
          USB_G_PRINTER = module;
          USB_G_SERIAL = module;
          USB_G_WEBCAM = module;
          USB_MASS_STORAGE = module;
        };
      }
    ];

    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
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
    firewall.interfaces.usb0.allowedUDPPorts = [
      67 # DHCPv4
      5353 # mDNS
    ];
    wireless.iwd.enable = true;
  };

  systemd = {
    network.networks = {
      # NOTE: DNSOverTLS requires accurate time, which I don't have yet across power loss without an RTC battery.
      "10-ether".networkConfig.DNSOverTLS = lib.mkForce false;
      "20-wlan-station".networkConfig.DNSOverTLS = lib.mkForce false;
      "30-usb-gadget" = {
        matchConfig.Name = "usb0";
        networkConfig = {
          MulticastDNS = true;
          DHCPServer = true;
          Address = "192.168.128.129/30";
        };
        dhcpServerConfig = {
          UplinkInterface = ":none";
          EmitDNS = false;
          EmitRouter = false;
        };
      };
    };

    services."serial-getty@ttyGS0" = {
      wants = [ "modprobe@g_cdc.service" ];
      after = [ "modprobe@g_cdc.service" ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}
