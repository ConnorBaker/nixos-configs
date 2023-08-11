{lib, ...}: let
  # Merge all of the configurations for a disk.
  mkDisk = name: {
    interface,
    model,
    serial,
    modelSerialSeparator,
    contentConfigs,
  }: {
    device = "/dev/disk/by-id/${interface}-${model}${modelSerialSeparator}${serial}";
    type = "disk";
    # Recursively merged all the configs for a disk.
    # NOTE: Because we use foldr, later configs override earlier configs.
    content = lib.foldr lib.recursiveUpdate {} contentConfigs;
  };

  # Configuration for our boot
  bootConfig = {
    type = "gpt";
    partitions = {
      boot = {
        size = "1M";
        type = "EF02"; # for grub MBR
      };
      ESP = {
        size = "1G";
        type = "EF00"; # EFI System
        content = {
          format = "vfat";
          mountpoint = "/boot";
          type = "filesystem";
        };
      };
    };
  };

  # Configuration for rpool disks.
  rpoolConfig = {
    type = "gpt";
    partitions.rpool = {
      size = "100%";
      type = "BF00"; # Solaris Root
      content = {
        type = "zfs";
        pool = "rpool";
      };
    };
  };

  hdds = let
    common = {
      interface = "ata";
      modelSerialSeparator = "-";
    };
    disks = {
      rpool-boot = {
        model = "ST12000NM0017";
        serial = "2A1111_ZJV05SVK";
        contentConfigs = [
          bootConfig
          rpoolConfig
        ];
      };
      rpool-data1 = {
        model = "ST12000NM003G";
        serial = "2MT113_ZL2GNTPA";
        contentConfigs = [rpoolConfig];
      };
    };
  in
    lib.mapAttrs (lib.const (lib.recursiveUpdate common)) disks;

  disks = hdds;
in {
  disko.devices.disk = lib.mapAttrs mkDisk disks;
}
