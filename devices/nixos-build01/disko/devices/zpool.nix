{lib, ...}:
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

    datasets = {
      root = {
        type = "zfs_fs";
        mountpoint = "/";
        postCreateHook = "zfs snapshot rpool/root@blank";
      };

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
