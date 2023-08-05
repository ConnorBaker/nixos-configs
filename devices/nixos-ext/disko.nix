{lib, ...}: let
  samsung990Pro2TBDisks = let
    interface = "nvme";
    model = "Samsung_SSD_990_PRO_2TB";
    modelSerialSeparator = "_";
  in {
    boot = {
      inherit interface model modelSerialSeparator;
      serial = "S73WNJ0W608017P";
      contentConfigs = [
        bootDiskContentConfig
        dataDiskContentConfig
      ];
    };
    data1 = {
      inherit interface model modelSerialSeparator;
      serial = "S73WNJ0W608883V";
      contentConfigs = [dataDiskContentConfig];
    };
    data2 = {
      inherit interface model modelSerialSeparator;
      serial = "S73WNJ0W608886J";
      contentConfigs = [dataDiskContentConfig];
    };
    data3 = {
      inherit interface model modelSerialSeparator;
      serial = "S73WNJ0W608887H";
      contentConfigs = [dataDiskContentConfig];
    };
  };

  disks = samsung990Pro2TBDisks;

  # Configuration for our boot
  bootDiskContentConfig = {
    type = "gpt";
    partitions.ESP = {
      size = "1G";
      type = "EF00"; # EFI System
      content = {
        format = "vfat";
        mountpoint = "/boot";
        type = "filesystem";
      };
    };
  };

  # Shared configuration for our data disks.
  # NOTE: We also use this for our boot disk.
  dataDiskContentConfig = {
    type = "gpt";
    partitions.rpool = {
      size = "100%";
      type = "BF00"; # Solaris Root
      content = {
        type = "zfs";
        pool = "rpool";
      };
    };
  };

  # Recursively merged all the configs for a disk.
  # NOTE: Because we use foldr, later configs override earlier configs.
  combineContentConfigs = lib.foldr (lib.recursiveUpdate) {};

  mkDisk = name: {
    interface,
    model,
    serial,
    modelSerialSeparator ? "-",
    contentConfigs,
  }: {
    device = "/dev/disk/by-id/${interface}-${model}${modelSerialSeparator}${serial}";
    type = "disk";
    content = combineContentConfigs contentConfigs;
  };

  zfsPoolCommonConfig = {
    type = "zpool";
    mode = "raidz2";
    options = {
      ashift = "12";
      autotrim = "on";
    };
    rootFsOptions = {
      acltype = "posixacl";
      atime = "off";
      canmount = "off";
      compression = "zstd";
      checksum = "sha512";
      dnodesize = "auto";
      normalization = "formD";
      xattr = "sa";
      "com.sun:auto-snapshot" = "false";
    };
    # TODO(@connorbaker): How do mountpoint and options.mountpoint differ?
    # datasets.reserved = {
    #   type = "zfs_fs";
    #   options = {
    #     canmount = "off";
    #     mountpoint = "none";
    #     reservation = "200G";
    #   };
    # };
  };
in {
  boot = {
    initrd.supportedFilesystems = ["zfs"];
    kernelParams = ["nohibernate"];
    supportedFilesystems = ["zfs"];
    # TODO(@connorbaker): Sadly, cannot be avoided right now. Needed because the nixos-anywhere
    # installer doesn't successfully unmount/export nested datasets.
    # zfs.forceImportRoot = false;
    zfs.enableUnstable = true;
  };

  disko.devices = {
    disk = lib.mapAttrs mkDisk disks;
    zpool.rpool = lib.recursiveUpdate zfsPoolCommonConfig {
      # TODO(@connorbaker): sharesmb option?
      # TODO(@connorbaker): Check ZFS features:
      # - https://openzfs.github.io/openzfs-docs/man/7/zpool-features.7.html#FEATURES

      # NOTE: This mountpoint doesn't pass the option to zpool create -- it's for NixOS'
      # fileSystems attribute set.
      mountpoint = "/";
      # NOTE: As such, we have to use rootFsOptions.mountpoint as well.
      rootFsOptions.mountpoint = "/";
      # postCreateHook = "zfs snapshot rpool@blank";

      datasets = {
        # TODO(@connorbaker): Create dataset torrent mirroring
        # - https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html#bit-torrent
        # - https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html#sequential-workloads
        # root = {
        #   type = "zfs_fs";
        #   mountpoint = "/";
        # };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
        };
        home = {
          type = "zfs_fs";
          mountpoint = "/home";
        };
        var = {
          type = "zfs_fs";
          mountpoint = "/var";
        };
        # "nixos/var/lib" = {
        #   type = "zfs_fs";
        #   mountpoint = "/var/lib";
        # };
        # "nixos/var/log" = {
        #   type = "zfs_fs";
        #   mountpoint = "/var/log";
        # };

        # encrypted = {
        #   type = "zfs_fs";
        #   options = {
        #     mountpoint = "none";
        #     encryption = "aes-256-gcm";
        #     keyformat = "passphrase";
        #     keylocation = "file:///tmp/secret.key";
        #   };
        #   # use this to read the key during boot
        #   # postCreateHook = ''
        #   #   zfs set keylocation="prompt" "rpool/$name";
        #   # '';
        # };
        # "encrypted/test" = {
        #   type = "zfs_fs";
        #   mountpoint = "/zfs_crypted";
        # };
      };
    };
  };

  networking.hostId = "deadbee5";

  nixpkgs.overlays = [
    (_: prev: {
      zfs = prev.zfsUnstable.overrideAttrs (oldAttrs: {
        patches =
          (oldAttrs.patches or [])
          #  Patch set for ZSTD 1.5.5
          ++ [
            # All-in-one patch set.
            # Substituted commit hashes for master on both branches.
            # To regenerate, replace with the new commit hashes.
            (prev.fetchpatch {
              hash = "";
              url = "https://github.com/openzfs/zfs/compare/5bdfff5cfc8baff48b3b59a577e7ef756a011024...b5a2a40945ab2a722d042eab35709d78ea12ef04.patch";
            })
            # merge zstd 1.5.4
            # (fetchpatch {
            #   hash = "";
            #   url = "https://github.com/openzfs/zfs/commit/9dfb0b28b1c3839d749bff5cab8ac2d1c6ddfd08.patch";
            # })
            # disable debug bloat
            # (fetchpatch {
            #   hash = "";
            #   url = "https://github.com/openzfs/zfs/commit/ce546b6d2f0e326a1c1dcc1f727fa02b51289946.patch";
            # })
            # update zstd to 1.5.5
            # (fetchpatch {
            #   hash = "";
            #   url = "https://github.com/openzfs/zfs/commit/04c89e8bd1af169d2d2b492fed189a4a7765dd2f.patch";
            # })
            # fixes broken aarch64 inline assembly for gcc 13.1
            # (fetchpatch {
            #   hash = "";
            #   url = "https://github.com/openzfs/zfs/commit/b5a2a40945ab2a722d042eab35709d78ea12ef04.patch";
            # })
          ];
      });
    })
  ];

  services = {
    # The following is from:
    # https://github.com/numtide/srvos/blob/ce0426c357c077edec3aacde8e9649f30f1be659/nixos/common/zfs.nix#L13-L16
    # ZFS has its own scheduler.
    udev.extraRules = ''
      ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*", ENV{ID_FS_TYPE}=="zfs_member", ATTR{../queue/scheduler}="none"
    '';
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };
  };
}
