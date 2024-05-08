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

  # Configuration for dpool disks.
  dpoolConfig = {
    type = "gpt";
    partitions.dpool = {
      size = "100%";
      type = "BF00"; # Solaris Root
      content = {
        type = "zfs";
        pool = "dpool";
      };
    };
  };

  samsung990Pro2TBDisks =
    let
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
          contentConfigs = [ rpoolConfig ];
        };
        rpool-data2 = {
          serial = "S73WNJ0W608886J";
          contentConfigs = [ rpoolConfig ];
        };
        rpool-data3 = {
          serial = "S73WNJ0W608887H";
          contentConfigs = [ rpoolConfig ];
        };
      };
    in
    lib.mapAttrs (lib.const (lib.recursiveUpdate common)) disks;

  seagateIronWolfPro22TBDisks =
    let
      common = {
        interface = "ata";
        model = "ST22000NT001";
        modelSerialSeparator = "-";
        contentConfigs = [ dpoolConfig ];
      };
      disks = {
        # dpool-data1.serial = "3LS101_ZX2097FT";
        # dpool-data2.serial = "3LS101_ZX2098PJ";
        # dpool-data3.serial = "3LS101_ZX209S8D";
        # dpool-data4.serial = "3LS101_ZX20AVT6";
        # dpool-data5.serial = "3LS101_ZX20BM3G";
        # dpool-data6.serial = "3LS101_ZX20BNTW";
        dpool-data7.serial = "3LS101_ZX20CWHS";
        dpool-data8.serial = "3LS101_ZX20LAQZ";
        # dpool-data9.serial = "3LS101_ZX20LARM";
        dpool-data10.serial = "3LS101_ZX20LM5X";
        # dpool-data11.serial = "3LS101_ZX20Q86S";
        dpool-data12.serial = "3LS101_ZX20TYZX";
      };
    in
    lib.mapAttrs (lib.const (lib.recursiveUpdate common)) disks;

  disks = samsung990Pro2TBDisks; # // seagateIronWolfPro22TBDisks;
in
{
  config.disko.devices.disk = lib.mapAttrs mkDisk disks;
}
