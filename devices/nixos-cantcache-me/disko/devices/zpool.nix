{ lib, ... }:
let
  zfsPoolCommonConfig = {
    type = "zpool";
    mode = "mirror";
    options = {
      ashift = "12";
      autotrim = "on";
    };
    rootFsOptions = {
      "com.sun:auto-snapshot" = "false";
      acltype = "posixacl";
      atime = "off";
      canmount = "off";
      checksum = "blake3"; # blake3 is the best, but we want speed
      compression = "zstd"; # Usually zstd, but we want speed
      dedup = "off";
      dnodesize = "auto";
      normalization = "formD";
      redundant_metadata = "most";
      sync = "disabled"; # Don't wait for data to be written to disk
      xattr = "sa";
    };
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
      };

      tmp = {
        type = "zfs_fs";
        mountpoint = "/tmp";
      };

      home = {
        type = "zfs_fs";
        mountpoint = "/home";
      };

      atticd = {
        type = "zfs_fs";
        mountpoint = "/var/lib/atticd";
        options.recordsize = "64K";
      };

      postgres = {
        type = "zfs_fs";
        mountpoint = "/var/lib/postgresql";
        options.recordsize = "16K";
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
