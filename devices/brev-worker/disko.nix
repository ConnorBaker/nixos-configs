{ lib, ... }:
let
  inherit ((import ../../util.nix { inherit lib; }).disko)
    zfsBootConfig
    zfsRpoolConfig
    zfsStripedPoolCommonConfig
    zfsRpoolDatasets
    ;
in
{
  # The instance's one EBS volume (gp3 at its defaults; Brev sets no other
  # type). Only this script names it: the system mounts the ESP by partition
  # label and the rest by pool, so every instance gets the same script and
  # system. On Nitro types the root EBS volume is the first NVMe device,
  # with instance-store disks after it (m8a.8xlarge and m8id.8xlarge,
  # 2026-10-26). AWS does not promise the order, so brev-worker checks in the
  # installer, before formatting, that nvme0n1 is the only EBS volume.
  disko.devices = {
    disk.rpool-boot = {
      device = "/dev/nvme0n1";
      type = "disk";
      content = lib.foldr lib.recursiveUpdate { } [
        zfsBootConfig
        zfsRpoolConfig
      ];
    };

    zpool.rpool = lib.recursiveUpdate zfsStripedPoolCommonConfig {
      # gp3 caps the volume at 125 MiB/s and 3000 IOPS by default, while 32
      # cores have time to spare: compression trades some of that time for
      # fewer bytes through the cap.
      rootFsOptions.compression = "zstd";
      datasets = zfsRpoolDatasets;
    };
  };
}
