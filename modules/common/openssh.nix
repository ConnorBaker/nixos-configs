{
  services.openssh = {
    allowSFTP = false;
    enable = true;
    settings.PasswordAuthentication = false;
  };
}
