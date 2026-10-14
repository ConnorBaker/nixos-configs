{
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko.nix

    # Secrets
    ./secrets.nix

    ../../profiles/builder.nix
    ../../modules/services/prometheus-exporters.nix
  ];

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadbee5";
    hostName = "nixos-ext";
  };

  users.users.connorbaker.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ61iahx0HtGVD0qtBFIr8nTPivNxQimrqaloBazYCPK john@nixos"
  ];

  system.stateVersion = "24.05";
}
