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
    device = "/dev/disk/by-id/ata-ST16000NM003G-2KH113_ZL2AE5N5";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "100M";
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
# TODO(@connorbaker): Switch to GPT example with EF02 flag if this fails.