{
  config,
  lib,
  ...
}: {
  fileSystems."/persist".neededForBoot = true;

  environment.persistence."/persist" = {
    directories =
      [
        "/var/log"
        "/var/lib"
      ]
      ++ lib.optionals config.programs.ccache.enable [
        config.programs.ccache.cacheDir
      ];
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/tailscale/tskey-reusable"
    ];
  };
}
