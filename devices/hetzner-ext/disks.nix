# # Example to create a bios compatible gpt partition
# {
#   disko.devices.disk.vdb = {
#     device = "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2AE5N5";
#     type = "disk";
#     content = {
#       type = "gpt";
#       partitions = {
#         boot = {
#           size = "2M";
#           type = "EF02"; # for grub MBR
#         };
#         root = {
#           size = "100%";
#           content = {
#             type = "btrfs";
#             extraArgs = ["-f"]; # Override existing partition
#             subvolumes = {
#               # Subvolume name is different from mountpoint
#               "/rootfs" = {
#                 mountpoint = "/";
#               };
#               # Mountpoints inferred from subvolume name
#               "/home" = {
#                 mountOptions = ["compress=zstd"];
#               };
#               "/nix" = {
#                 mountOptions = ["compress=zstd" "noatime"];
#               };
#               "/test" = {};
#             };
#           };
#         };
#       };
#     };
#   };
# }
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2AE5N5";
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
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
