{ lib }:
{
  disko = {
    zfsStripedPoolCommonConfig = {
      type = "zpool";
      mode = ""; # Stripe the data; no redundancy!
      options = {
        ashift = "12";
        autotrim = "on";
      };
      rootFsOptions = {
        "com.sun:auto-snapshot" = "false";
        acltype = "posixacl";
        atime = "off";
        canmount = "off";
        checksum = "off"; # blake3 is the best, but we want speed
        compression = "off"; # Usually zstd, but we want speed
        dedup = "off";
        dnodesize = "auto";
        normalization = "formD";
        redundant_metadata = "none";
        sync = "disabled"; # Don't wait for data to be written to disk
        xattr = "sa";
      };
    };

    # Shared ephemeral root and persistent datasets for every rpool.
    zfsRpoolDatasets = {
      root = {
        type = "zfs_fs";
        mountpoint = "/";
        postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^rpool/root@blank$' || zfs snapshot rpool/root@blank";
      };

      nix = {
        type = "zfs_fs";
        mountpoint = "/nix";
        # NOTE: Although on average we have a large number of small files, and 4k is the page size of the SQLite
        # database Nix uses, changing to such a small recordsize has a negative impact on read/write performance for
        # flash storage. Additionally, the SQLite database isn't under heavy usage constantly, so there's no need to
        # optimize for it.
      };

      tmp = {
        type = "zfs_fs";
        mountpoint = "/tmp";
      };

      home = {
        type = "zfs_fs";
        mountpoint = "/home";
      };

      # Persist hosts things like /etc/ssh/ssh_host_* keys, /var/lib and /var/log.
      persist = {
        type = "zfs_fs";
        mountpoint = "/persist";
      };
    };

    # Configuration for our boot
    zfsBootConfig = {
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

    # Configuration for rpool disks.
    zfsRpoolConfig = {
      type = "gpt";
      partitions.rpool = {
        size = "100%";
        content = {
          type = "zfs";
          pool = "rpool";
        };
      };
    };

    # Merge all of the configurations for a disk.
    mkDisk =
      {
        interface,
        model,
        serial,
        modelSerialSeparator,
        contentConfigs,
      }:
      {
        device = "/dev/disk/by-id/${interface}-${model}${modelSerialSeparator}${serial}";
        type = "disk";
        # Recursively merged all the configs for a disk.
        # NOTE: Because we use foldr, later configs override earlier configs.
        content = lib.foldr lib.recursiveUpdate { } contentConfigs;
      };
  };

  # What a Nix configuration file sets, read as Nix reads it, for checks of
  # the files a daemon reads rather than of the options that wrote them.
  # Here and in spark-nix-infra's check.
  nixConf =
    let
      # A line's text before any comment, split on whitespace
      # (tokenizeString).
      words =
        line:
        lib.filter (word: builtins.isString word && word != "") (
          builtins.split "[[:space:]]+" (builtins.head (builtins.split "#" line))
        );
      # Older names of the settings the checks read (libstore's
      # local-settings.hh and worker-settings.hh).
      aliases = {
        build-use-chroot = "sandbox";
        build-use-sandbox = "sandbox";
        build-max-jobs = "max-jobs";
      };
    in
    {
      # nix.conf (libutil/configuration.cc): each `name = value` line sets
      # its setting, a later line winning, and an empty value is a value.
      # include lines set nothing here; `includes` lists them.
      settings =
        text:
        lib.foldl' (
          set: line:
          let
            line' = words line;
            name = builtins.head line';
          in
          if
            line' == [ ]
            || builtins.elem name [
              "include"
              "!include"
            ]
          then
            set
          else if builtins.length line' < 2 || builtins.elemAt line' 1 != "=" then
            throw "not a nix.conf line: ${line}"
          else
            set // { ${aliases.${name} or name} = lib.concatStringsSep " " (lib.drop 2 line'); }
        ) { } (lib.splitString "\n" text);

      # The include and !include lines of a nix.conf, as their words.
      includes =
        text:
        lib.filter (
          line:
          line != [ ]
          && builtins.elem (builtins.head line) [
            "include"
            "!include"
          ]
        ) (map words (lib.splitString "\n" text));

      # A machines file (libstore/machines.cc): an entry per line or per
      # `;`, its fields split on whitespace, `-` meaning none. Only the
      # fields the checks read, and the URI's host.
      machines =
        text:
        lib.concatMap (
          line:
          map
            (
              entry:
              let
                fields = words entry;
                field = i: if builtins.length fields > i then builtins.elemAt fields i else "-";
                uri = field 0;
              in
              if uri == "-" || lib.hasPrefix "@" uri then
                throw "not a machines entry this check reads: ${entry}"
              else
                {
                  inherit uri;
                  host = builtins.elemAt (builtins.match "([^:/]+://)?([^@/]+@)?([^:/?@]+).*" uri) 2;
                  mandatoryFeatures = lib.optionals (field 6 != "-") (
                    lib.filter (feature: feature != "") (lib.splitString "," (field 6))
                  );
                }
            )
            (
              lib.filter (entry: words entry != [ ]) (
                lib.splitString ";" (builtins.head (builtins.split "#" line))
              )
            )
        ) (lib.splitString "\n" text);
    };
}
