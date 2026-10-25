{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../packages/zfs-fideduperange { inherit lib; }) withFideduperange;
  zfsPkg = config.boot.zfs.package;
in
{
  boot = {
    extraModprobeConfig = ''
      # Retain the existing workload tuning; compare against 5–10 seconds
      # under representative builds before changing it. Block cloning is
      # already enabled by default in OpenZFS 2.3 and later.
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
    };
    kernelPackages = lib.mkIf (
      !config.hardware.nvidia-jetpack.enable or false
    ) pkgs.linuxKernel.packages.linux_7_2;
    kernelParams = [
      # Nixpkgs already adds nohibernate for ZFS and asserts networking.hostId.
      # https://github.com/openzfs/zfs/issues/9910
      "init_on_alloc=0"
      "init_on_free=0"
    ];
    zfs = {
      # Prefer availability for remote hosts without KVM access: force-import
      # root after unclean shutdowns or installer boots that did not export pools.
      forceImportRoot = true;
      # Userspace and kernel module carry the same FIDEDUPERANGE backport.
      # modulePackage is selected the way nixpkgs' zfs module does it.
      package = withFideduperange pkgs.zfs_unstable;
      modulePackage = withFideduperange config.boot.kernelPackages.${zfsPkg.kernelModuleAttribute};
    };
  };

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };

  systemd = {
    # Disko/NixOS fileSystems own the systemd mounts. Native ZFS mountpoint
    # properties name /rpool/... rather than the /nix, /home, /tmp, /persist
    # paths we actually mount; enabling zfs-mount would add a second manager.
    services.zfs-mount.enable = false;
  };
}
