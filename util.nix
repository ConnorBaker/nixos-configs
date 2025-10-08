{ lib }:
{
  disko = {
    zfsStripedPoolCommonConfig = {
      type = "zpool";
      mode = ""; # Stripe the data; no redundancy!
      options = {
        ashift = "12";
        autotrim = "on";
      };
      rootFsOptions = {
        "com.sun:auto-snapshot" = "false";
        acltype = "posixacl";
        atime = "off";
        canmount = "off";
        checksum = "off"; # blake3 is the best, but we want speed
        compression = "off"; # Usually zstd, but we want speed
        dedup = "off";
        dnodesize = "auto";
        normalization = "formD";
        redundant_metadata = "none";
        sync = "disabled"; # Don't wait for data to be written to disk
        xattr = "sa";
      };
    };

    # Configuration for our boot
    zfsBootConfig = {
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
    zfsRpoolConfig = {
      type = "gpt";
      partitions.rpool = {
        size = "100%";
        content = {
          type = "zfs";
          pool = "rpool";
        };
      };
    };

    # Merge all of the configurations for a disk.
    mkDisk =
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
  };
}
