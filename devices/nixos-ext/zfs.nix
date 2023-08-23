{config, lib, pkgs, ...}: {
  boot = {
    initrd = {
      # NOTE: Return to the initial snapshot.
      postDeviceCommands = lib.mkAfter ''
        zfs rollback -r rpool@blank
        zfs rollback -r dpool@blank
      '';
      supportedFilesystems = ["vfat" "zfs"];
    };
    kernelParams = ["nohibernate"];
    supportedFilesystems = ["vfat" "zfs"];
    # NOTE: Sadly, cannot be avoided right now. Needed because the nixos-anywhere
    # installer doesn't successfully unmount/export nested datasets.
    # zfs.forceImportRoot = true;
    # NOTE: Required for datasets nested under the root dataset? Seems like there's a race
    # condition with Systemd's import service.
    # zfs.forceImportAll = true;
  };

  # Copied from https://github.com/NixOS/nixpkgs/issues/62644#issuecomment-1479523469
  systemd.generators."zfs-mount-generator" = "${config.boot.zfs.package}/lib/systemd/system-generator/zfs-mount-generator";
  environment.etc."zfs/zed.d/history_event-zfs-list-cacher.sh".source = "${config.boot.zfs.package}/etc/zfs/zed.d/history_event-zfs-list-cacher.sh";
  systemd.services.zfs-mount.enable = false;
  services.zfs.zed.settings.PATH = lib.mkForce (lib.makeBinPath [
    pkgs.diffutils
    config.boot.zfs.package
    pkgs.coreutils
    pkgs.curl
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.nettools
    pkgs.util-linux
  ]);

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
