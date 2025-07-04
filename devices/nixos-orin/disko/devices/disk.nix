{ lib, ... }:
let
  # Merge all of the configurations for a disk.
  mkDisk =
    _name:
    {
      interface,
      model,
      serial,
      modelSerialSeparator,
      contentConfigs,
    }:
    {
      device = "/dev/disk/by-id/${interface}-${model}${modelSerialSeparator}${serial}";
      type = "disk";
      # Recursively merged all the configs for a disk.
      # NOTE: Because we use foldr, later configs override earlier configs.
      content = lib.foldr lib.recursiveUpdate { } contentConfigs;
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
      content = {
        type = "zfs";
        pool = "rpool";
      };
    };
  };

  samsung990Pro2TBDisk =
    let
      common = {
        interface = "nvme";
        model = "Samsung_SSD_990_PRO_2TB";
        modelSerialSeparator = "_";
      };
      disks = {
        rpool-boot = {
          serial = "S73WNJ0W809592D";
          contentConfigs = [
            bootConfig
            rpoolConfig
          ];
        };
        rpool-data = {
          serial = "S73WNJ0W809592D";
          contentConfigs = [ rpoolConfig ];
        };
      };
    in
    lib.mapAttrs (lib.const (lib.recursiveUpdate common)) disks;
in
{
  config.disko.devices.disk = lib.mapAttrs mkDisk samsung990Pro2TBDisk;
}
