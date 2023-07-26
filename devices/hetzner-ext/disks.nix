{lib, ...}: let
  # TODO(@connorbaker):
  #
  # We cannot use the full disk ID and default label naming scheme due to length limitations.
  #
  # For example, using the ID "ata-ST16000NM003G-2KH113_ZL2AE5N5" results in the following error:
  #
  # mkfs.vfat: unable to open /dev/disk/by-partlabel/disk-ata-ST16000NM003G-2KH113_ZL2AE5N5-ESP: No such file or directory
  #
  # Looking at the contents of /dev/disk/by-partlabel, we see the following:
  #
  # disk-ata-ST16000NM003G-2KH113_ZL2AE5
  #
  # Notice the truncated name!
  #
  # To work around this, we will name the disks by their serial.
  diskInterface = "ata";
  diskModel = "ST16000NM003G";
  diskSerials = [
    "2KH113_ZL2AE5N5"
    "2KH113_ZL2BTF3N"
    "2KH113_ZL2CABRF"
    "2KH113_ZL2CAW73"
  ];
  # Choose the first disk as the disk to store the boot partition.
  bootDiskConfig = lib.genAttrs [(builtins.head diskSerials)] (diskSerial: {
    device = "/dev/disk/by-id/${diskInterface}-${diskModel}-${diskSerial}";
    type = "disk";
    content = {
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
  });
  zfsDiskConfigs = lib.genAttrs diskSerials (diskSerial: {
    device = "/dev/disk/by-id/${diskInterface}-${diskModel}-${diskSerial}";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        zfs = {
          size = "100%";
          content = {
            type = "zfs";
            pool = "zroot";
          };
        };
      };
    };
  });
in {
  disko.devices = {
    disk = lib.recursiveUpdate bootDiskConfig zfsDiskConfigs;
    zpool = {
      zroot = {
        # Setup
        type = "zpool";
        mode = "mirror"; # ZFS Mode, string
        options = {
          # Sector size (logical/physical): 512 bytes / 4096 bytes
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          atime = "off";
          compression = "zstd";
          dnodesize = "auto";
          normalization = "formD";
          utf8only = "on";
          xattr = "sa";
          # TODO(@connorbaker): sharesmb option?
          "com.sun:auto-snapshot" = "false";
          # TODO(@connorbaker): Check ZFS features:
          # - https://openzfs.github.io/openzfs-docs/man/7/zpool-features.7.html#FEATURES
          # TODO(@connorbaker): Check DRAID instead of RAIDZ or mirror.
        };
        mountpoint = "/";
        # mountOptions = {}; # Options for the root filesystem attrset of strings
        postCreateHook = "zfs snapshot zroot@blank";

        # Datasets
        datasets = {
          # TODO(@connorbaker): Create dataset torrent mirroring
          # - https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html#bit-torrent
          # - https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html#sequential-workloads
          # zfs_fs = {
          #   type = "zfs_fs";
          #   mountpoint = "/zfs_fs";
          #   options."com.sun:auto-snapshot" = "true";
          # };
          # encrypted = {
          #   type = "zfs_fs";
          #   options = {
          #     mountpoint = "none";
          #     encryption = "aes-256-gcm";
          #     keyformat = "passphrase";
          #     keylocation = "file:///tmp/secret.key";
          #   };
          #   # use this to read the key during boot
          #   # postCreateHook = ''
          #   #   zfs set keylocation="prompt" "zroot/$name";
          #   # '';
          # };
          # "encrypted/test" = {
          #   type = "zfs_fs";
          #   mountpoint = "/zfs_crypted";
          # };
        };
      };
    };
  };
}
