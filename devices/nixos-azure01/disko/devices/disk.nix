{ lib, ... }:
let
  # Configuration for our boot
  bootConfig = {
    type = "gpt";
    partitions.ESP = {
      size = "1G";
      type = "EF00"; # EFI System
      content = {
        format = "vfat";
        mountpoint = "/boot";
        mountOptions = [ "umask=0077" ];
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
in
{
  config.disko.devices.disk = {
    boot = {
      device = "/dev/sda";
      type = "disk";
      content = bootConfig;
    };
    zero = {
      device = "/dev/sdb";
      type = "disk";
      content.type = "gpt";
    };
    rpool-data1 = {
      device = "/dev/nvme0n1";
      type = "disk";
      content = rpoolConfig;
    };
    rpool-data2 = {
      device = "/dev/nvme1n1";
      type = "disk";
      content = rpoolConfig;
    };
  };
}
