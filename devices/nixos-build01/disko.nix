{ lib, ... }:
let
  inherit ((import ../../util.nix { inherit lib; }).disko)
    mkDisk
    zfsBootConfig
    zfsRpoolConfig
    zfsStripedPoolCommonConfig
    zfsRpoolDatasets
    ;
in
{
  disko.devices = {
    disk =
      let
        common = {
          interface = "nvme";
          model = "Samsung_SSD_990_PRO_2TB";
          modelSerialSeparator = "_";
        };
      in
      lib.mapAttrs (_: value: mkDisk (common // value)) {
        rpool-boot = {
          serial = "S73WNJ0W701713F";
          contentConfigs = [
            zfsBootConfig
            zfsRpoolConfig
          ];
        };
        rpool-data1 = {
          serial = "S73WNJ0W701716V";
          contentConfigs = [ zfsRpoolConfig ];
        };
        rpool-data2 = {
          serial = "S73WNJ0W701722Z";
          contentConfigs = [ zfsRpoolConfig ];
        };
        rpool-data3 = {
          serial = "S73WNJ0W701726F";
          contentConfigs = [ zfsRpoolConfig ];
        };
      };

    zpool.rpool = lib.recursiveUpdate zfsStripedPoolCommonConfig {
      datasets = zfsRpoolDatasets;
    };
  };
}
