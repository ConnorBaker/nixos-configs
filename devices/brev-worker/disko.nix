{ lib, ... }:
let
  inherit ((import ../../util.nix { inherit lib; }).disko)
    zfsStripedPoolCommonConfig
    zfsRpoolDatasets
    ;
in
{
  # m8id: everything on the instance-store NVMe, which is far faster than
  # EBS (gp3, 125 MiB/s by default; nix-brev's README has measurements) and
  # survives reboots but not a stop and start, which these instances never
  # get. The EBS volume, which the firmware boots from and AWS requires,
  # holds only the ESP (GRUB, kernels, initrds and nix-brev's rescue
  # installer); nix-brev creates it at Brev's minimum, 10 GiB.
  #
  # By PCI path: the kernel numbers the NVMe devices in probe order, which
  # differed between boots of the same m8id instance, while the root EBS
  # volume sits at 0000:00:04.0 and the instance store at 0000:33:00.0 on
  # every m8a and m8id seen (2026-10-26). nix-brev checks both, by model,
  # before formatting.
  disko.devices = {
    disk.boot = {
      device = "/dev/disk/by-path/pci-0000:00:04.0-nvme-1";
      type = "disk";
      content = {
        type = "gpt";
        partitions.ESP = {
          size = "100%";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
      };
    };

    disk.nvme = {
      device = "/dev/disk/by-path/pci-0000:33:00.0-nvme-1";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          # zram's backing device (default.nix); a raw partition.
          zram-writeback.size = "256G";
          rpool = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "rpool";
            };
          };
        };
      };
    };

    zpool.rpool = lib.recursiveUpdate zfsStripedPoolCommonConfig {
      # On the instance store a kernel build took 74.6 s with zstd and
      # 74.0 s without (brev-x86-15), and zstd shrank the tree 3.54x, which
      # the compressed ARC holds as well.
      rootFsOptions.compression = "zstd";
      datasets = zfsRpoolDatasets;
    };
  };
}
