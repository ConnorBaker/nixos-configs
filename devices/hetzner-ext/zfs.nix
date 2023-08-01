{
  config,
  lib,
  ...
}: let
  # TODO(@connorbaker):
  #
  # We cannot use the full disk ID and default label naming scheme due to length limitations.
  #
  # For example, using the ID "ata-ST16000NM003G-2KH113_ZL2AE5N5" results in the following error:
  #
  # mkfs.vfat: unable to open /dev/disk/by-partlabel/disk-ata-ST16000NM003G-2KH113_ZL2AE5N5-ESP: No such file or directory
  #
  # Looking at the contents of /dev/disk/by-partlabel, we see the following:
  #
  # disk-ata-ST16000NM003G-2KH113_ZL2AE5
  #
  # Notice the truncated name!
  #
  # To work around this, we name each disk.
  disks = {
    boot = {
      interface = "ata";
      model = "ST12000NM0017";
      serial = "2A1111_ZJV05SVK";
      contentConfigs = [
        bootDiskContentConfig
        dataDiskContentConfig
      ];
    };
    data = {
      interface = "ata";
      model = "ST12000NM003G";
      serial = "2MT113_ZL2GNTPA";
      contentConfigs = [dataDiskContentConfig];
    };
  };

  # Configuration for our boot
  bootDiskContentConfig = {
    type = "gpt";
    partitions = {
      boot = {
        size = "1M";
        type = "EF02"; # for grub MBR
      };
      ESP = {
        size = "512M";
        type = "EF00";
        content = {
          format = "vfat";
          mountpoint = "/boot";
          type = "filesystem";
        };
      };
    };
  };

  # Shared configuration for our data disks.
  # NOTE: We also use this for our boot disk.
  dataDiskContentConfig = {
    type = "gpt";
    partitions.zfs = {
      size = "100%";
      content = {
        type = "zfs";
        pool = "zroot";
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
    contentConfigs,
  }: {
    device = "/dev/disk/by-id/${interface}-${model}-${serial}";
    type = "disk";
    content = combineContentConfigs contentConfigs;
  };
in {
  boot = {
    initrd.supportedFilesystems = ["zfs"];
    # kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
    kernelParams = ["nohibernate"];
    loader.grub = {
      copyKernels = true;
      efiSupport = false;
      enable = true;
    };
    supportedFilesystems = ["zfs"];
    zfs = {
      enableUnstable = true;
      forceImportRoot = false;
    };
  };

  disko.devices = {
    disk = lib.mapAttrs mkDisk disks;
    zpool = {
      zroot = {
        # Setup
        type = "zpool";
        mode = "mirror"; # ZFS Mode, string
        options = {
          # Sector size (logical/physical): 512 bytes / 4096 bytes
          ashift = "12";
          # autotrim = "on";
        };
        rootFsOptions = {
          # acltype = "posixacl";
          # atime = "off";
          # compression = "zstd";
          # dnodesize = "auto";
          # normalization = "formD";
          # utf8only = "on";
          # xattr = "sa";
          # TODO(@connorbaker): sharesmb option?
          "com.sun:auto-snapshot" = "false";
          # TODO(@connorbaker): Check ZFS features:
          # - https://openzfs.github.io/openzfs-docs/man/7/zpool-features.7.html#FEATURES
        };
        mountpoint = "/";
        # mountOptions = {}; # Options for the root filesystem attrset of strings
        # postCreateHook = "zfs snapshot zroot@blank";

        # Datasets
        datasets = {
          # TODO(@connorbaker): Create dataset torrent mirroring
          # - https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html#bit-torrent
          # - https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html#sequential-workloads
          # zfs_fs = {
          #   type = "zfs_fs";
          #   mountpoint = "/zfs_fs";
          #   options."com.sun:auto-snapshot" = "true";
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
          #   #   zfs set keylocation="prompt" "zroot/$name";
          #   # '';
          # };
          # "encrypted/test" = {
          #   type = "zfs_fs";
          #   mountpoint = "/zfs_crypted";
          # };
        };
      };
    };
  };

  networking.hostId = "deadbee5";

  nixpkgs.overlays = [
    (_: prev: {
      zfs = let
        inherit (prev) fetchpatch zfs;
      in
        zfs.overrideAttrs (oldAttrs: {
          patches =
            (oldAttrs.patches or [])
            # Performance patches
            ++ [
              # btree: Implement faster binary search algorithm
              # (fetchpatch {
              #   hash = "";
              #   url = "https://github.com/ryao/zfs/commit/bbe335089844f05c46cb30a9ee4061117c6c683f.patch";
              # })
              # Use __attribute__((malloc)) on memory allocation functions
              # (fetchpatch {
              #   hash = "";
              #   url = "https://github.com/ryao/zfs/commit/53044a6157ac62b91fb27f2bb775ef1b92e3e850.patch";
              # })
            ]
            #  Patch set for ZSTD 1.5.5
            ++ [
              # All-in-one patch set.
              # Substituted commit hashes for master on both branches.
              # To regenerate, replace with the new commit hashes.
              # (fetchpatch {
              #   hash = "";
              #   url = "https://github.com/openzfs/zfs/compare/5bdfff5cfc8baff48b3b59a577e7ef756a011024...b5a2a40945ab2a722d042eab35709d78ea12ef04.patch";
              # })
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

  # TODO(@connorbaker): Freezes when using ZFS?
  # https://github.com/numtide/srvos/blob/ce0426c357c077edec3aacde8e9649f30f1be659/nixos/common/zfs.nix#L13-L16
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
}
