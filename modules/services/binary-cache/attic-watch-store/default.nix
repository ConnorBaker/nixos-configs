{ pkgs, ... }:

# Creates a systemd service which runs attic watch-store
let
  user = "attic-watch-store";
  atticWatchStoreConfig = "${user}/config.toml";
in
{
  # NOTE: File should contain:
  # default-server = "cuda-server-push"
  # [servers.cuda-server-push]
  # endpoint = "https://direct.cantcache.me"
  # token = <cuda-builder token as created in README.md>
  sops.secrets.${atticWatchStoreConfig} = {
    owner = user;
    mode = "0440";
    path = "/var/lib/${user}/.config/attic/config.toml";
    sopsFile = ./secrets.yaml;
  };

  systemd.services.${user} = {
    description = "Attic watch-store service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.attic}/bin/attic watch-store cuda-server-push:cuda";
      Restart = "on-failure";
      RestartSec = "30s";
      StartLimitBurst = 3;
      User = user;
      Group = user;
      SyslogIdentifier = user;
    };
  };
  users = {
    groups.${user} = { };
    users.${user} = {
      isSystemUser = true;
      home = "/var/lib/${user}";
      createHome = true;
      group = user;
    };
  };
}
