{
  config,
  lib,
  pkgs,
  ...
}: {
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
    zfs.enableUnstable = true;
    kernelPackages = pkgs.linuxKernel.packages.linux_6_4;
  };

  # Some settings copied from https://github.com/NixOS/nixpkgs/issues/62644#issuecomment-1479523469
  environment.etc."zfs/zed.d/history_event-zfs-list-cacher.sh".source = "${config.boot.zfs.package}/etc/zfs/zed.d/history_event-zfs-list-cacher.sh";

  networking.hostId = "deadba5e";

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
      # Add pkgs.diffutils to PATH for zed (required for zfs-mount-generator).
      zed.settings.PATH = lib.mkForce (lib.makeBinPath [
        config.boot.zfs.package
        pkgs.coreutils
        pkgs.curl
        pkgs.diffutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.nettools
        pkgs.util-linux
      ]);
    };
  };

  systemd = {
    generators.zfs-mount-generator = "${config.boot.zfs.package}/lib/systemd/system-generator/zfs-mount-generator";
    services.zfs-mount.enable = false;
  };
}
