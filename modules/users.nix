{
  users.mutableUsers = false;
  # TODO: Is this necessary?
  systemd.user.extraConfig = "DefaultLimitNOFILE=32000";
}
