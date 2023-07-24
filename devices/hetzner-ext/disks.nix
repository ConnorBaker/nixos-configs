{
  disko.devices.disk.main = {
    # NOTE: We can use short names for the devices since we mount them by
    # the label we create.
    device = "/dev/sda";
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
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [
              "--force"
              "--label"
              "nixos"
              "--data"
              "raid1"
              "--metadata"
              "raid1"
              "/dev/sdb"
              "/dev/sdc"
              "/dev/sdd"
            ];
            subvolumes = {
              # Subvolume name is different from mountpoint
              "/rootfs" = {
                mountOptions = ["compress=zstd"];
                mountpoint = "/";
              };
              # Mountpoints inferred from subvolume name
              "/home" = {
                mountOptions = ["compress=zstd"];
              };
              "/nix" = {
                mountOptions = ["compress=zstd" "noatime"];
              };
            };
          };
        };
      };
    };
  };
}
