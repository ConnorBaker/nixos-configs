{
  environment.variables.BROWSER = "echo";
  fonts.fontconfig.enable = false;
  systemd.sleep.extraConfig = ''
    AllowHibernation=no
    AllowSuspend=no
  '';
  time.timeZone = "UTC";
}
