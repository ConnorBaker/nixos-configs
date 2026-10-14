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

    # Shared ephemeral root and persistent datasets for every rpool.
    zfsRpoolDatasets = {
      root = {
        type = "zfs_fs";
        mountpoint = "/";
        postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^rpool/root@blank$' || zfs snapshot rpool/root@blank";
      };

      nix = {
        type = "zfs_fs";
        mountpoint = "/nix";
        # NOTE: Although on average we have a large number of small files, and 4k is the page size of the SQLite
        # database Nix uses, changing to such a small recordsize has a negative impact on read/write performance for
        # flash storage. Additionally, the SQLite database isn't under heavy usage constantly, so there's no need to
        # optimize for it.
      };

      tmp = {
        type = "zfs_fs";
        mountpoint = "/tmp";
      };

      home = {
        type = "zfs_fs";
        mountpoint = "/home";
      };

      # Persist hosts things like /etc/ssh/ssh_host_* keys, /var/lib and /var/log.
      persist = {
        type = "zfs_fs";
        mountpoint = "/persist";
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
