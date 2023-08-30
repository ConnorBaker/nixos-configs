{lib, ...}: {
  fileSystems."/persist".neededForBoot = true;

  environment.persistence."/persist" = {
    directories = [
      "/var/log"
      "/var/lib"
    ];
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/tailscale/tskey-reusable"
    ];
  };

  # Use ZFS to reset the root pool.
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r rpool@blank
  '';
}
