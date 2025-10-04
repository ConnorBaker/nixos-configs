{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "thunderbolt"
      "vmd"
      "xhci_pci"
    ];
    kernelModules = [ "kvm-intel" ];
    kernelParams = [ "intel_pstate=active" ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  hardware = {
    cpu.intel.updateMicrocode = true;
    enableAllFirmware = true;
    graphics.enable = true;
    nvidia = {
      nvidiaPersistenced = false;
      open = true;
      package = config.boot.kernelPackages.nvidiaPackages.beta;
      powerManagement.enable = true;
    };
  };

  powerManagement.cpuFreqGovernor = "performance";

  programs.nix-required-mounts =
    let
      thingDriverLinkLinksTo =
        config.systemd.tmpfiles.settings.graphics-driver."/run/opengl-driver"."L+".argument;
    in
    {
      enable = true;
      presets.nvidia-gpu.enable = true;
      # NOTE: addDriverRunpath.driverLink links to /run/opengl-driver.
      # That is in turn a symlink, created by this:
      # https://github.com/NixOS/nixpkgs/blob/c82d9d313d5107c6ad3a92fc7d20343f45fa5ace/nixos/modules/hardware/graphics.nix#L5-L8
      # That derivation isn't exposed except as a path, used here:
      # https://github.com/NixOS/nixpkgs/blob/c82d9d313d5107c6ad3a92fc7d20343f45fa5ace/nixos/modules/hardware/graphics.nix#L112-L121
      # In order for the symlink /run/opengl-driver to be able to resolve, we need to add the thing it points to as well.
      # The other paths include the NVIDIA and Mesa drivers, so we don't need to include them here.
      allowedPatterns.nvidia-gpu.paths = [ thingDriverLinkLinksTo ];
    };

  services.xserver.videoDrivers = [ "nvidia" ];

  systemd.network.networks."10-ether" =
    let
      cfg = config.systemd.network.networks."10-ether";
    in
    {
      linkConfig.MACAddress = "58:11:22:b4:9d:69";

      networkConfig = {
        Address = "192.168.1.12/24";
        Gateway = "192.168.1.1";
        DHCP = lib.mkForce "ipv6";
      };

      # IPv4 Static Leases
      dhcpServerStaticLeases = [
        {
          inherit (cfg.linkConfig) MACAddress;
          Address = lib.removeSuffix "/24" cfg.networkConfig.Address;
        }
      ];

      routes = lib.mkBefore [
        {
          inherit (cfg.networkConfig) Gateway;
          GatewayOnLink = true;
        }
        { Destination = cfg.networkConfig.Gateway; }
      ];
    };
}
