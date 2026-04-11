{
  environment.variables.BROWSER = "echo";
  fonts.fontconfig.enable = false;
  systemd.sleep.settings.Sleep = {
    AllowHibernation = "no";
    AllowSuspend = "no";
  };
  time.timeZone = "UTC";
}
