{lib, ...}:
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
      content = {
        type = "zfs";
        pool = "rpool";
      };
    };
  };

  samsung9xxProDisks =
    let
      common = {
        interface = "nvme";
        modelSerialSeparator = "_";
      };
      disks = {
        rpool-boot = {
          model = "Samsung_SSD_990_PRO_1TB";
          serial = "S73VNJ0TA10611H";
          contentConfigs = [
            bootConfig
            rpoolConfig
          ];
        };
        rpool-data1 = {
          model = "Samsung_SSD_980_PRO_2TB";
          serial = "S6B0NL0W218445N";
          contentConfigs = [rpoolConfig];
        };
        rpool-data2 = {
          model = "Samsung_SSD_980_PRO_2TB";
          serial = "S6B0NL0W218446M";
          contentConfigs = [rpoolConfig];
        };
      };
    in
    lib.mapAttrs (lib.const (lib.recursiveUpdate common)) disks;
in
{
  config.disko.devices.disk = lib.mapAttrs mkDisk samsung9xxProDisks;
}
