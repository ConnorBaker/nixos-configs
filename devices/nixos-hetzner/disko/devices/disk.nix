{lib, ...}: let
  # Merge all of the configurations for a disk.
  mkDisk = name: {
    interface,
    model,
    serial,
    modelSerialSeparator,
    contentConfigs,
  }: {
    device = "/dev/disk/by-id/${interface}-${model}${modelSerialSeparator}${serial}";
    type = "disk";
    # Recursively merged all the configs for a disk.
    # NOTE: Because we use foldr, later configs override earlier configs.
    content = lib.foldr lib.recursiveUpdate {} contentConfigs;
  };

  # Configuration for our boot
  bootConfig = {
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
  rpoolConfig = {
    type = "gpt";
    partitions.rpool = {
      size = "100%";
      type = "BF00"; # Solaris Root
      content = {
        type = "zfs";
        pool = "rpool";
      };
    };
  };

  samsungPM9A3Disks = let
    common = {
      interface = "nvme";
      model = "SAMSUNG_MZQL21T9HCJR";
      modelSerialSeparator = "-";
    };
    disks = {
      rpool-boot = {
        serial = "00A07_S64GNN0W300145";
        contentConfigs = [
          bootConfig
          rpoolConfig
        ];
      };
      rpool-data = {
        serial = "00A07_S64GNN0W300147";
        contentConfigs = [rpoolConfig];
      };
    };
  in
    lib.mapAttrs (lib.const (lib.recursiveUpdate common)) disks;
in {
  config.disko.devices.disk = lib.mapAttrs mkDisk samsungPM9A3Disks;
}
