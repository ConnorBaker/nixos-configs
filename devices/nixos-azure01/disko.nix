{ lib, ... }:
let
  inherit ((import ../../util.nix { inherit lib; }).disko)
    zfsBootConfig
    zfsRpoolConfig
    zfsStripedPoolCommonConfig
    ;

  # TODO(@connorbaker): Why did we need mountOptions? Did we? Was this just erroneously copy-pasted?
  zfsBootConfig' = lib.recursiveUpdate zfsBootConfig {
    partitions.ESP.content.mountOptions = [ "umask=0077" ];
  };
in
{
  disko.devices = {
    disk = {
      # TODO(@connorbaker): One of /dev/sda and /dev/sdb is the disk the device boots from.
      # It's unclear which one will be *the* boot device...
      # See hardware.nix for the janky way we add the udev rules for ephemeral azure instances.
      boot = {
        device = "/dev/sda";
        type = "disk";
        content = zfsBootConfig';
      };
      zero = {
        device = "/dev/sdb";
        type = "disk";
        content.type = "gpt";
      };
      rpool-data1 = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = zfsRpoolConfig;
      };
      rpool-data2 = {
        device = "/dev/nvme1n1";
        type = "disk";
        content = zfsRpoolConfig;
      };
    };

    zpool.rpool = lib.recursiveUpdate zfsStripedPoolCommonConfig {
      datasets = {
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
    };
  };
}
