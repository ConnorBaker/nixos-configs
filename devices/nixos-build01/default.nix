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
    hostId = "deadba5e";
    hostName = "nixos-build01";
  };

  system.stateVersion = "24.05";
}
