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
    initrd = {
      # Use ZFS to reset the root pool.
      postDeviceCommands = lib.mkAfter ''
        zfs rollback -r rpool/root@blank
      '';
      supportedFilesystems = [
        "vfat"
        "zfs"
      ];
    };
    kernelPackages = pkgs.linuxKernel.packages.linux_6_7;
    kernelParams = [ "nohibernate" ];
    supportedFilesystems = [
      "vfat"
      "zfs"
    ];
    zfs.enableUnstable = true;
  };

  # Some settings copied from https://github.com/NixOS/nixpkgs/issues/62644#issuecomment-1479523469
  environment.etc."zfs/zed.d/history_event-zfs-list-cacher.sh".source = "${zfsPkg}/etc/zfs/zed.d/history_event-zfs-list-cacher.sh";

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
    # Add pkgs.diffutils to PATH for zed (required for zfs-mount-generator).
    zed.settings.PATH = lib.mkForce (
      lib.makeBinPath [
        zfsPkg
        pkgs.coreutils
        pkgs.curl
        pkgs.diffutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.nettools
        pkgs.util-linux
      ]
    );
  };

  systemd = {
    generators.zfs-mount-generator = "${zfsPkg}/lib/systemd/system-generator/zfs-mount-generator";
    services.zfs-mount.enable = false;
  };
}
