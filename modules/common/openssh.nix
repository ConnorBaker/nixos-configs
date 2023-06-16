{
  services.openssh = {
    allowSFTP = true;
    enable = true;
    settings.PasswordAuthentication = false;
  };
}
