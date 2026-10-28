{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../packages/zfs-fideduperange { inherit lib; }) withFideduperange;
  zfsPkg = config.boot.zfs.package;
  # The FIDEDUPERANGE backport goes to nixos-ext and nixos-desktop only. The
  # other hosts keep stock zfs_unstable, and nixpkgs' zfs module picks its
  # kernel module, as before the backport.
  fideduperange = lib.elem config.networking.hostName [
    "nixos-desktop"
    "nixos-ext"
  ];
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
    # linux_7_2 hides an exiting OOM victim from memcg OOM scans (a72f73c4dd9b,
    # "cgroup: Don't expose dead tasks in cgroup"), so a scan that runs while
    # the victim frees its memory kills a second task. The patch passes
    # CSS_TASK_ITER_WITH_DEAD in mem_cgroup_scan_tasks(), which restores the
    # scan's pre-a72f73c4dd9b behaviour: a single-threaded victim stays
    # visible until its mm is MMF_OOM_SKIP. A multi-threaded victim whose
    # leader has exited, with a non-leader doing the last mmput(), can still
    # be missed; 6.18 has the same gap, so that is not a regression. The patch
    # is ours, not upstream's: `git format-patch` of a commit on linux-stable
    # v7.2.12 (cc9de5d4b5ab), checked with `patch -p1 --dry-run` against
    # nixpkgs' linux-7.2.12.tar.xz, and tested against the unpatched kernel in
    # a VM test. Same condition as kernelPackages: nixos-orin runs L4T's 5.15,
    # and a72f73c4dd9b went to stable 6.19 and later only. The README has the
    # mechanism, the evidence, the affected kernels and when to drop it.
    kernelPatches = lib.mkIf (!config.hardware.nvidia-jetpack.enable or false) [
      {
        name = "memcg-oom-scan-with-dead";
        patch = ../packages/linux-memcg-oom-scan/0001-mm-memcontrol-let-memcg-OOM-scans-see-exiting-OOM-vi.patch;
      }
    ];
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
      # Where it applies, userspace and kernel module carry the same
      # FIDEDUPERANGE backport. modulePackage is selected the way nixpkgs'
      # zfs module does it.
      package = if fideduperange then withFideduperange pkgs.zfs_unstable else pkgs.zfs_unstable;
      modulePackage = lib.mkIf fideduperange (
        withFideduperange config.boot.kernelPackages.${zfsPkg.kernelModuleAttribute}
      );
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
