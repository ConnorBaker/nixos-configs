{lib, ...}: {
  boot = {
    initrd = {
      # NOTE: Return to the initial snapshot.
      postDeviceCommands = lib.mkAfter ''
        zfs rollback -r rpool@blank
      '';
      supportedFilesystems = ["vfat" "zfs"];
    };
    kernelParams = ["nohibernate"];
    supportedFilesystems = ["vfat" "zfs"];
    # NOTE: Sadly, cannot be avoided right now. Needed because the nixos-anywhere
    # installer doesn't successfully unmount/export nested datasets.
    zfs.forceImportRoot = false;
  };

  networking.hostId = "deadbee5";

  services = {
    # The following is adapted from:
    # https://github.com/numtide/srvos/blob/ce0426c357c077edec3aacde8e9649f30f1be659/nixos/common/zfs.nix#L13-L16
    # ZFS has its own scheduler.
    udev.extraRules = lib.strings.concatStringsSep ", " [
      "ACTION==\"add|change\""
      "KERNEL==\"sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*\""
      "ENV{ID_FS_TYPE}==\"zfs_member\""
      "ATTR{../queue/scheduler}=\"none\""
    ];
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };
  };
}
