{
  config,
  lib,
  pkgs,
  ...
}:
let
  inventory = import ../../inventory.nix;
  isHub = config.networking.hostName == inventory.hub;
  # Concurrent Tribuchet builds per worker. Builds run with cores = 0, so
  # each may use every core: two already saturate a 32-core host, which
  # also runs our own compiles and analyses. Each build needs one agent.
  # spark-nix-infra (the Spark and Brev workers) uses the same value.
  jobs = 2;
in
{
  imports = [ ./nix-grpc-store.nix ];
  services.tribuchet-hub = lib.mkIf isHub {
    enable = true;
    package = pkgs.tribuchet;
    openFirewall = false;
    externalBuilders = {
      enable = true;
      # The hub derives external-builders systems and max-jobs from the
      # workers currently connected, rewriting a nix.conf fragment that
      # nix-daemon is restarted on; systems no worker serves stay local.
      dynamic = true;
      # Bound the hub-emitted max-jobs by this host's uid slots: every
      # offloaded build still holds one locally (id-count / 65536).
      maxJobsCap = (config.nix.settings.id-count or (128 * 65536)) / 65536;
      nixPackage = pkgs.nix;
      patchNix = false;
    };
    settings = {
      auth = "tailscale";
      tailscale-allowed-tags = [ "tag:ci" ];
    };
  };

  services.tribuchet-worker = {
    enable = true;
    package = pkgs.tribuchet;
    agents = jobs;
    settings = {
      auth = "tailscale";
      hub = "http://${inventory.hub}.${inventory.tailnet}:7437";
      max-jobs = jobs;
      recursive-nix = true;
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf isHub [ 7437 ];

  systemd.services.tribuchet-worker = {
    after = [ "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled-autoconnect.service" ];
  };
}
