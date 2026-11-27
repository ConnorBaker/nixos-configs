{
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko.nix

    # Secrets
    ./secrets.nix

    ../../profiles/builder.nix
    ../../modules/services/prometheus-exporters.nix
    ../../modules/watchdog.nix
  ];

  environment.etc = {
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    hostId = "deadabcd";
    hostName = "nixos-desktop";
  };

  # A KVM host: 8 builds at once, one per agent. It relies on the hub's
  # admission by learned memory (Tribuchet 691f58f4).
  services.tribuchet-worker.agents = 8;

  system.stateVersion = "24.05";
}
