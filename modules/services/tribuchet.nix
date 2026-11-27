{
  config,
  lib,
  pkgs,
  ...
}:
let
  inventory = import ../../inventory.nix;
  isHub = config.networking.hostName == inventory.hub;
  worker = config.services.tribuchet-worker;
  # Concurrent Tribuchet builds per worker, where the host does not set its
  # own. Builds run with cores = 0, so each may use every core: two already
  # saturate a 32-core host, which also runs our own compiles and analyses.
  # Each build needs one agent. The Brevs (devices/brev-worker) set
  # agents = "auto": one agent, and one build, per CPU. spark-nix-infra
  # (the Spark) sets 2 itself.
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
      # The known workers as a farm, for the hub's nix-grpc-daemon to admit
      # builds by (its farmFile, modules/services/nix-grpc-store.nix).
      farmPath = "/run/tribuchet/farm.json";
      # Bounds only the max-jobs line the hub writes into the nix.conf
      # fragment (the connected agents' capacity, oversubscribed); the
      # builds the hub holds at once are bounded by nix's uid slots
      # (id-count), not by this.
      maxJobsCap = 256;
      # It is the hub's nix.package (modules/nix/generation-plugins.nix).
      nixPackage = config.system.build.nixWithGenerationPlugins;
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
    agents = lib.mkDefault jobs;
    # The hub runs beside the agents here, outside their slice, which is
    # capped at MemTotal less this reserve (and less MemTotal/16 for its
    # zswap; modules/services/tribuchet-agent-memory.nix). The option's
    # default (8 GiB) leaves nothing for the hub. On nixos-ext on
    # 2026-11-27, 3.8 days after a start, tribuchet-hub.service held
    # 10.25 GB, nearly all anonymous (MemoryPeak 10.56 GB = 9.83 GiB) and
    # unswappable (MemorySwapMax = 0 below), so the default left the slice
    # 79.66 GiB of 93.51 GiB beside ~14 GB of other units. Keep the default
    # for the rest of the host and add the hub's peak, rounded up to a GiB.
    agentMemoryReserve = lib.mkIf isHub ((8 + 10) * 1024 * 1024 * 1024);
    settings = {
      auth = "tailscale";
      hub = "http://${inventory.hub}.${inventory.tailnet}:7437";
      # One build per agent. Unset with agents = "auto", the worker's own
      # default is one per CPU too.
      max-jobs = lib.mkIf (worker.agents != "auto") worker.agents;
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf isHub [ 7437 ];

  systemd = {
    services = {
      # The hub service is WantedBy=multi-user.target but only ordered After= its
      # socket. A switch that starts multi-user.target can then start the service
      # without the socket; the service binds the listeners itself and the socket
      # refuses to start ("already active"), failing the switch. Requiring the
      # socket puts its start job in the same transaction, ordered first.
      tribuchet-hub = lib.mkIf isHub {
        requires = [ "tribuchet-hub.socket" ];
        # Keep the hub's anonymous memory in RAM: at both watchdog kills on
        # 2026-10-25 it was 88-94% swapped out, and a runtime worker stalled
        # 14 s in a swap-in. This limits only this unit's cgroup, where no
        # build runs (builds run under nix-daemon and the Tribuchet agents).
        serviceConfig.MemorySwapMax = "0";
      };

      tribuchet-worker = {
        after = [ "tailscaled-autoconnect.service" ];
        wants = [ "tailscaled-autoconnect.service" ];
      };
    };
  };
}
