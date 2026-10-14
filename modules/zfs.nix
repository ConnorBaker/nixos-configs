{
  config,
  lib,
  pkgs,
  ...
}:
# TODO: Find a way to implement a check which makes certain networking.hostId is set.
let
  zfsPkg = config.boot.zfs.package;
in
{
  boot = {
    # TODO: Investigate potential tuneables in
    # https://github.com/openzfs/zfs/issues/8381#issuecomment-1374268868
    extraModprobeConfig = ''
      # Enable block cloning for ZFS.
      options zfs zfs_bclone_enabled=1
      # Values to increase the time before ZFS TXG timeout.
      options zfs zfs_txg_timeout=30
    '';
    initrd = {
      # Use ZFS to reset the root pool.
      systemd.services.zfs-rollback-root = {
        description = "Rollback ZFS root dataset";
        after = [ "zfs-import-rpool.service" ];
        before = [
          "sysroot.mount"
          "zfs-import.target"
        ];
        requiredBy = [
          "sysroot.mount"
          "zfs-import.target"
        ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${zfsPkg}/sbin/zfs rollback -r rpool/root@blank
        '';
      };
      supportedFilesystems = [
        "vfat"
        "zfs"
      ];
    };
    kernelPackages = lib.mkIf (
      !config.hardware.nvidia-jetpack.enable or false
    ) pkgs.linuxKernel.packages.linux_6_18;
    kernelParams = [
      "nohibernate"

      # https://github.com/openzfs/zfs/issues/9910
      "init_on_alloc=0"
      "init_on_free=0"
    ];
    supportedFilesystems = [
      "vfat"
      "zfs"
    ];
    # Prefer availability for remote hosts without KVM access: force-import
    # root after unclean shutdowns or installer boots that did not export pools.
    zfs.forceImportRoot = true;
    zfs.package = pkgs.zfs_unstable;
  };

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };

  systemd = {
    services.zfs-mount.enable = false;
  };
}
