{
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2AE5N5";
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
              "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2BTF3N"
              "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2CABRF"
              "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2CAW73"
            ];
            subvolumes = {
              # Subvolume name is different from mountpoint
              "/rootfs" = {
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
