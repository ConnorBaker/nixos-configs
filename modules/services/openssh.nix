{
  networking.firewall.allowedTCPPorts = [22];
  services.openssh = {
    allowSFTP = true;
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      X11Forwarding = false;
    };
  };
}
