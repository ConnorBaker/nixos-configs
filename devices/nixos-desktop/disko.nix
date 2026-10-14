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
          modelSerialSeparator = "_";
        };
      in
      lib.mapAttrs (_: value: mkDisk (common // value)) {
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
      datasets = zfsRpoolDatasets;
    };
  };
}
