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
    partitions.ESP = {
      size = "1G";
      type = "EF00"; # EFI System
      content = {
        format = "vfat";
        mountpoint = "/boot";
        type = "filesystem";
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

  samsung990Pro2TBDisks = let
    common = {
      interface = "nvme";
      model = "Samsung_SSD_990_PRO_2TB";
      modelSerialSeparator = "_";
    };
    disks = {
      rpool-boot = {
        serial = "S73WNJ0W608017P";
        contentConfigs = [
          bootConfig
          rpoolConfig
        ];
      };
      rpool-data1 = {
        serial = "S73WNJ0W608883V";
        contentConfigs = [rpoolConfig];
      };
      rpool-data2 = {
        serial = "S73WNJ0W608886J";
        contentConfigs = [rpoolConfig];
      };
      rpool-data3 = {
        serial = "S73WNJ0W608887H";
        contentConfigs = [rpoolConfig];
      };
    };
  in
    lib.mapAttrs (lib.const (lib.recursiveUpdate common)) disks;

  disks = samsung990Pro2TBDisks;
in {
  config.disko.devices.disk = lib.mapAttrs mkDisk disks;
}