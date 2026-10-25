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
    # Placement A/B: /run/tribuchet/placement-arm (fcfs, speed-only,
    # speed-demand or count) overrides `arm` at every decision. Keyed by
    # worker name; a value some candidate lacks is left out of that
    # decision. speed: nixos-ext's low-load wall over the worker's, same
    # pnames (calibrate.py); 1.0 unless the interval is outside 0.9-1.1.
    # cores, memoryGiB: nproc and MemTotal read from the hosts 2026-10-25.
    placement = {
      arm = "fcfs";
      workers = {
        nixos-ext = {
          speed = 1.0;
          cores = 32;
          memoryGiB = 93.5;
        };
        nixos-desktop = {
          speed = 1.0;
          cores = 32;
          memoryGiB = 94.0;
        };
        # m8a.8xlarge, us-east-1a. speed: set from the calibration step
        # before the first A/B block; until then it is left out.
        brev-x86-10 = {
          cores = 32;
          memoryGiB = 123.5;
        };
        brev-x86-11 = {
          cores = 32;
          memoryGiB = 123.5;
        };
        brev-x86-12 = {
          cores = 32;
          memoryGiB = 123.5;
        };
      };
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

  # The hub service is WantedBy=multi-user.target but only ordered After= its
  # socket. A switch that starts multi-user.target can then start the service
  # without the socket; the service binds the listeners itself and the socket
  # refuses to start ("already active"), failing the switch. Requiring the
  # socket puts its start job in the same transaction, ordered first.
  systemd.services.tribuchet-hub = lib.mkIf isHub {
    requires = [ "tribuchet-hub.socket" ];
  };

  systemd.services.tribuchet-worker = {
    after = [ "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled-autoconnect.service" ];
  };
}
