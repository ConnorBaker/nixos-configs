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
          serial = "S73WNJ0W809592D";
          contentConfigs = [
            zfsBootConfig
            zfsRpoolConfig
          ];
        };
      };

    zpool.rpool = lib.recursiveUpdate zfsStripedPoolCommonConfig {
      datasets = zfsRpoolDatasets;
    };
  };
}
