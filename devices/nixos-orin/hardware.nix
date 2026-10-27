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
      # Nixpkgs dropped kernels older than 6.1 (NixOS/nixpkgs@3fe146e66071)
      # and now patches every kernel's scripts/gen-randstruct-seed.sh, added in
      # 5.19, after these patches. Add the script as 5.19 has it so that patch
      # applies to L4T's 5.15. Nothing runs it: 5.15 generates the seed with
      # scripts/gcc-plugins/gen-random-seed.sh, and only for
      # GCC_PLUGIN_RANDSTRUCT, which neither L4T nor NixOS enables here.
      {
        name = "add-gen-randstruct-seed";
        patch = ./add-gen-randstruct-seed.patch;
      }
    ];

    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  hardware = {
    # Jetpack derives CUDA support from this; assigning driver packages alone
    # does not enable graphics.
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
      "10-ether".networkConfig.DNSOverTLS = false;
      "20-wlan-station".networkConfig.DNSOverTLS = false;
      "05-usb-gadget" = {
        matchConfig.Name = "usb0";
        networkConfig = {
          MulticastDNS = true;
          DHCP = "no";
          DHCPServer = true;
          IPv6AcceptRA = false;
          LinkLocalAddressing = "ipv6";
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
      # macOS going to sleep causes the service to die
      serviceConfig.Restart = "always";
    };
  };
}
