{ lib, ... }:
let
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
      checksum = "blake3";
      dnodesize = "auto";
      normalization = "formD";
      xattr = "sa";
      "com.sun:auto-snapshot" = "false";
    };
  };

  rpool = lib.recursiveUpdate zfsPoolCommonConfig {
    # TODO(@connorbaker): sharesmb option?

    # NOTE: This mountpoint doesn't pass the option to zpool create -- it's for NixOS'
    # fileSystems attribute set.
    mountpoint = "/";
    # NOTE: As such, we have to use rootFsOptions.mountpoint as well.
    rootFsOptions.mountpoint = "/";

    # NOTE: We use this to create the initial snapshot.
    postCreateHook = ''
      zfs snapshot rpool@blank
    '';

    datasets = {
      nix = {
        type = "zfs_fs";
        mountpoint = "/nix";
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
  };
in
{
  disko.devices.zpool = {
    inherit rpool;
  };
}
