{ lib, ... }:
let
  zfsPoolCommonConfig = {
    type = "zpool";
    mode = ""; # Stripe the data; no redundancy!
    options = {
      ashift = "12";
      autotrim = "on";
    };
    rootFsOptions = {
      acltype = "posixacl";
      atime = "off";
      canmount = "off";
      compression = "zstd";
      checksum = "blake3";
      dnodesize = "auto";
      normalization = "formD";
      xattr = "sa";
      "com.sun:auto-snapshot" = "false";
    };
    # datasets.reserved = {
    #   type = "zfs_fs";
    #   options = {
    #     canmount = "off";
    #     mountpoint = "none";
    #     reservation = "200G";
    #   };
    # };
  };

  rpool = lib.recursiveUpdate zfsPoolCommonConfig {
    datasets = {
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

  dpool = lib.recursiveUpdate zfsPoolCommonConfig {
    # TODO(@connorbaker): sharesmb option?

    # NOTE: This mountpoint doesn't pass the option to zpool create -- it's for NixOS'
    # fileSystems attribute set.
    mountpoint = "/data";
    # NOTE: As such, we have to use rootFsOptions.mountpoint as well.
    rootFsOptions.mountpoint = "/data";

    # NOTE: We use this to create the initial snapshot.
    postCreateHook = ''
      zfs snapshot dpool@blank
    '';

    datasets = {
      # TODO(@connorbaker): Create dataset torrent mirroring
      # - https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html#bit-torrent
      # - https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html#sequential-workloads
      photos = {
        type = "zfs_fs";
        mountpoint = "/data/photos";
      };

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
in
{
  disko.devices.zpool = {
    inherit rpool;
    # TODO(@connorbaker): Disabled dpool temporarily; it was not successfully mounted on initial system installation.
  };
}
