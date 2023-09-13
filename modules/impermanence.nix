{
  fileSystems."/persist".neededForBoot = true;

  environment.persistence."/persist" = {
    directories = [
      "/var/log"
      "/var/lib"
    ];
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
    ];
  };
}
