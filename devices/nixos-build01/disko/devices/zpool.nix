{lib, ...}: let
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
      checksum = "sha512"; # TODO(@connorbaker): Switch to blake3 after ZFS 2.2.
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
in {
  disko.devices.zpool = {
    inherit rpool;
  };
}
