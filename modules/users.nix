{
  users.mutableUsers = false;
  systemd.user.extraConfig = "DefaultLimitNOFILE=32000";
}
