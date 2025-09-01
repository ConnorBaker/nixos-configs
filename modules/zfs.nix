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
      # TODO(@connorbaker): Disabled for nixos-azure01:
      # <<< NixOS Stage 1 >>>

      # loading module ata_piix...
      # loading module dm_mod...
      # loading module hv_netvsc...
      # loading module hv_storvsc...
      # loading module hv_utils...
      # loading module hv_vmbus...
      # loading module nls_cp437...
      # loading module nls_iso8859-1...
      # loading module vfat...
      # loading module zfs...
      # running udev...
      # Starting systemd-udevd version 257.7
      # kbd_mode: KDSKBMODE: Inappropriate ioctl for device
      # starting device mapper and LVM...
      # cannot open 'rpool/root@blank': dataset does not exist
      # importing root ZFS pool "rpool"...............................................................
      # cannot import 'rpool': no such pool available
      # filesystem 'rpool/persist' cannot be mounted, unable to open the dataset
      # umount: can't unmount /persist-tmp-mnt/persist: Invalid argument
      # mounting rpool/root on /...
      # filesystem 'rpool/root' cannot be mounted, unable to open the dataset
      # retrying...
      # EFI stub: Loaded initrd from LINUX_EFI_INITRD_MEDIA_GUID device path
      # [    0.000000] Linux version 6.16.3 (nixbld@localhost) (gcc (GCC) 14.3.0, GNU ld (GNU Binutils) 2.44) #1-NixOS SMP PREEMPT_DYNAMIC Sat Aug 23 14:49:42 UTC 2025
      # [    0.000000] Command line: initrd=\EFI\nixos\ml4vwp9g647wg4hh63bdn0sa1ky7bpyy-initrd-linux-6.16.3-initrd.efi init=/nix/store/6nqfvp6kg0jzmm70scvjq77qm7jrmibq-nixos-system-nixos-azure01-25.11.20250827.8a6d542/init console=ttyS0 earlyprintk=ttyS0 rootdelay=300 panic=1 boot.panic_on_fail nohibernate init_on_alloc=0 init_on_free=0 amd_pstate=active nohibernate loglevel=4 net.ifnames=0 lsm=landlock,yama,bpf
      # [    0.000000] BIOS-provided physical RAM map:
      # [    0.000000] BIOS-e820: [mem 0x0000000000000000-0x000000000009ffff] usable
      # [    0.000000] BIOS-e820: [mem 0x00000000000c0000-0x00000000000fffff] reserved
      # [    0.000000] BIOS-e820: [mem 0x0000000000100000-0x000000003ff40fff] usable
      # [    0.000000] BIOS-e820: [mem 0x000000003ff41000-0x000000003ffc8fff] reserved
      # [    0.000000] BIOS-e820: [mem 0x000000003ffc9000-0x000000003fffafff] ACPI data
      # [    0.000000] BIOS-e820: [mem 0x000000003fffb000-0x000000003fffefff] ACPI NVS
      # [    0.000000] BIOS-e820: [mem 0x000000003ffff000-0x000000003fffffff] usable
      # [    0.000000] BIOS-e820: [mem 0x0000000100000000-0x0000000fbfffffff] usable
      # [    0.000000] BIOS-e820: [mem 0x0000001000000000-0x00000072ffffffff] usable
      # [    0.000000] printk: legacy bootconsole [earlyser0] enabled
      # Memory KASLR using RDRAND RDTSC...
      # Poking KASLR using RDRAND RDTSC...
      # postDeviceCommands = lib.mkAfter ''
      #   zfs rollback -r rpool/root@blank
      # '';
      supportedFilesystems = [
        "vfat"
        "zfs"
      ];
    };
    kernelPackages = lib.mkIf (
      !config.hardware.nvidia-jetpack.enable or false
    ) pkgs.linuxKernel.packages.linux_6_16;
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
    zfs.package = pkgs.zfs_unstable;
  };

  # Some settings copied from https://github.com/NixOS/nixpkgs/issues/62644#issuecomment-1479523469
  environment.etc."zfs/zed.d/history_event-zfs-list-cacher.sh".source =
    "${zfsPkg}/etc/zfs/zed.d/history_event-zfs-list-cacher.sh";

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
