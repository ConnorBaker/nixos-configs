{
  users.mutableUsers = false;
  # TODO: Is this necessary?
  systemd.user.settings.Manager.DefaultLimitNOFILE = "32000";
}
