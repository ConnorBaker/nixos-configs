{lib, ...}: let
  disks = {
    boot = {
      interface = "ata";
      model = "ST12000NM0017";
      serial = "2A1111_ZJV05SVK";
      contentConfigs = [
        bootDiskContentConfig
        dataDiskContentConfig
      ];
    };
    # data = {
    #   interface = "ata";
    #   model = "ST12000NM003G";
    #   serial = "2MT113_ZL2GNTPA";
    #   contentConfigs = [dataDiskContentConfig];
    # };
  };

  # Configuration for our boot
  bootDiskContentConfig = {
    type = "gpt";
    partitions = {
      boot = {
        size = "1M";
        type = "EF02"; # for grub MBR
      };
      ESP = {
        size = "512M";
        type = "EF00";
        content = {
          format = "vfat";
          mountpoint = "/boot";
          type = "filesystem";
        };
      };
    };
  };

  # Shared configuration for our data disks.
  # NOTE: We also use this for our boot disk.
  dataDiskContentConfig = {
    type = "gpt";
    partitions.root = {
      size = "100%";
      content = {
        format = "ext4";
        mountpoint = "/";
        type = "filesystem";
      };
    };
  };

  # Recursively merged all the configs for a disk.
  # NOTE: Because we use foldr, later configs override earlier configs.
  combineContentConfigs = lib.foldr (lib.recursiveUpdate) {};

  mkDisk = name: {
    interface,
    model,
    serial,
    contentConfigs,
  }: {
    device = "/dev/disk/by-id/${interface}-${model}-${serial}";
    type = "disk";
    content = combineContentConfigs contentConfigs;
  };
in {
  boot = {
    kernelParams = ["nohibernate"];
    loader.grub = {
      copyKernels = true;
      efiSupport = false;
      enable = true;
    };
  };

  disko.devices.disk = lib.mapAttrs mkDisk disks;

  networking.hostId = "deadbee5";
}
