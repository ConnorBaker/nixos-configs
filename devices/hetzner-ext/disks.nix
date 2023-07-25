{lib, ...}: let
  disks = [
    "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2AE5N5"
    "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2BTF3N"
    "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2CABRF"
    "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2CAW73"
  ];
  # Choose the first disk as the disk to store the boot partition.
  mainDisk = builtins.elemAt disks 0;
  mainDiskConfig = {
    ${mainDisk} = {
      device = mainDisk;
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
    };
  };
  zfsDiskConfigs = lib.genAttrs disks (disk: {
    device = disk;
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
    disk = lib.recursiveUpdate mainDiskConfig zfsDiskConfigs;
    zpool = {
      zroot = {
        # Setup
        type = "zpool";
        mode = "mirror"; # ZFS Mode, string
        # options = {}; # Options for the ZFS pool attrset of strings
        rootFsOptions = {
          compression = "zstd";
          "com.sun:auto-snapshot" = "false";
        };
        mountpoint = "/";
        # mountOptions = {}; # Options for the root filesystem attrset of strings
        postCreateHook = "zfs snapshot zroot@blank";

        # Datasets
        datasets = {
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
