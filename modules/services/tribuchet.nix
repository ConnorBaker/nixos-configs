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
  # Placement A/B rotation window (UTC), e.g. { start =
  # "2026-10-27T08:00:00Z"; end = "2026-11-03T08:00:00Z"; }. Each hour in
  # it runs one arm; null leaves the arm file alone (hub.toml's arm).
  placementAB = null;
  rotating = isHub && placementAB != null;
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

      # At the top of each UTC hour in the window, write that hour's arm:
      # three hours per cycle, cycles taking the six orders of fcfs (F),
      # speed-only (S) and speed-demand (D) in turn. Outside the window the
      # file is removed, so hub.toml's fcfs applies. The hub reads the file
      # at every placement decision; nothing restarts.
      tribuchet-placement-arm = lib.mkIf rotating {
        description = "Write this hour's Tribuchet placement A/B arm";
        after = [ "tribuchet-hub.service" ];
        path = [ pkgs.coreutils ];
        serviceConfig.Type = "oneshot";
        script = ''
          file=/run/tribuchet/placement-arm
          now=$(date -u +%s)
          start=$(date -u -d ${placementAB.start} +%s)
          end=$(date -u -d ${placementAB.end} +%s)
          if [ "$now" -lt "$start" ] || [ "$now" -ge "$end" ]; then
            rm -f "$file"
            exit 0
          fi
          k=$((now / 3600 - start / 3600))
          orders=(FSD SDF DFS DSF FDS SFD)
          order=''${orders[$((k / 3 % 6))]}
          case ''${order:$((k % 3)):1} in
            F) arm=fcfs ;;
            S) arm=speed-only ;;
            D) arm=speed-demand ;;
          esac
          printf '%s\n' "$arm" > "$file.new"
          mv "$file.new" "$file"
          echo "hour $k of the window: $arm"
        '';
      };

      tribuchet-worker = {
        after = [ "tailscaled-autoconnect.service" ];
        wants = [ "tailscaled-autoconnect.service" ];
      };
    };

    timers.tribuchet-placement-arm = lib.mkIf rotating {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:00:00 UTC";
        AccuracySec = "1s";
        # /run is empty after a reboot.
        OnBootSec = "1min";
      };
    };
  };
}
