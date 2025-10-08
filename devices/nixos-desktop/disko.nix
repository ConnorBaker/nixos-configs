{ lib, ... }:
let
  inherit ((import ../../util.nix { inherit lib; }).disko)
    mkDisk
    zfsBootConfig
    zfsRpoolConfig
    zfsStripedPoolCommonConfig
    ;
in
{
  disko.devices = {
    disk =
      let
        common = {
          interface = "nvme";
          modelSerialSeparator = "_";
        };
      in
      lib.mapAttrs (name: value: mkDisk (common // value)) {
        rpool-boot = {
          model = "Samsung_SSD_990_PRO_1TB";
          serial = "S73VNJ0TA10611H";
          contentConfigs = [
            zfsBootConfig
            zfsRpoolConfig
          ];
        };
        rpool-data1 = {
          model = "Samsung_SSD_980_PRO_2TB";
          serial = "S6B0NL0W218445N";
          contentConfigs = [ zfsRpoolConfig ];
        };
        rpool-data2 = {
          model = "Samsung_SSD_980_PRO_2TB";
          serial = "S6B0NL0W218446M";
          contentConfigs = [ zfsRpoolConfig ];
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
