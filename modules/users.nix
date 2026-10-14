{
  users.mutableUsers = false;
  # Retain the increased soft limit without lowering systemd's hard ceiling.
  systemd.user.settings.Manager.DefaultLimitNOFILE = "32000:524288";
}
