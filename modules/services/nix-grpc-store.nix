{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Use exactly the optimized Nix libraries selected for the running daemon.
  grpc = config.programs.nix-grpc-store.packageSet.default;
  inventory = import ../../inventory.nix;
  hub = config.services.tribuchet-hub;
in
{
  programs.nix-grpc-store = {
    enable = true;
    packageSet = pkgs.nixGrpcPackages;
    # A single selected Nix ABI is enough; avoid building every release.
    package = grpc;
  };
  services.nix-grpc-daemon = {
    enable = true;
    package = grpc;
    # Tailscale supplies encryption and the existing tailnet policy controls
    # access. The host firewall opens this port on tailscale0 only.
    listen = "[::]:50051";
    # Remote builders must be able to import unsigned build inputs.
    trustClients = true;
    # One local gRPC endpoint per host; the ext Nix daemon schedules CPU jobs
    # through Tribuchet. No shared gRPC farm, balancer, or S3 service is needed.
    workerName = config.networking.hostName;
    # Builds taken at once, the GPU jobs other hosts' build hooks send. Unset,
    # it follows nix's max-jobs, which is 0 off the hub (one build at a time);
    # 2 is what that gave it before. On the hub, every build this daemon takes
    # waits in Tribuchet's own admission, so take as many as nix-daemon has
    # uid slots (servable() clamps to them anyway). Following Tribuchet's
    # max-jobs, the sum of connected agents, let builds queued for one system
    # hold every slot while workers of another sat idle. Always passed as
    # --max-jobs, so nix.conf rewrites and SIGHUP leave it alone.
    maxJobs = if hub.enable then config.nix.settings.id-count / 65536 else 2;
    # On the hub, admit a build only while the Tribuchet workers that could
    # build its class (system and required features) have room for it, so
    # that builds of a class few workers serve (aarch64-linux, kvm tests)
    # waiting there cannot hold the slots that plain x86_64-linux builds need.
    # Tribuchet writes it on every worker change; absent, nothing is bounded.
    farmFile = lib.mkIf hub.enable hub.externalBuilders.farmPath;
    # U51 stage 1: the before-measurement of ngs's own queue and pool
    # (nix_grpc_sched{kind="queued"}, nix_grpc_queue_seconds,
    # nix_grpc_build_slots, nix_grpc_inflight) ahead of the W33 uncap; see
    # fork-harness runs/w55-scheduling-comparison/REPORT.md. Loopback only.
    # Read once at process start: it takes effect at the next generation
    # (takeover or idle exit), not on switch or SIGHUP.
    metricsListen = lib.mkIf hub.enable "127.0.0.1:9464";
    # On the hub, nix-daemon hands each system a connected Tribuchet worker
    # serves to external-builders, including farm systems that are neither
    # its own nor in extra-platforms (the Spark's aarch64-linux). Offer
    # those too; otherwise the scheduler refuses their
    # builds with "no connected, non-draining worker for system ...".
    extraSystems = lib.mkIf hub.enable (
      lib.subtractLists [ pkgs.stdenv.hostPlatform.system ] (
        lib.unique (lib.concatMap (host: host.systems) (lib.attrValues inventory.hosts))
      )
    );
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 50051 ];

  systemd = {
    services = {
      # Leave a running daemon alone on switch. Upstream's reload is a drain,
      # which assumes other builders take the new builds; each host here is
      # its own scheduler's only builder, so the drain refused every new build
      # until the slowest running one finished (nixos-ext, 2026-10-25
      # 05:37-05:54Z). The new generation starts after --idle-timeout or a
      # deliberate restart.
      nix-grpc-daemon = {
        reloadIfChanged = lib.mkForce false;
        restartIfChanged = false;
      };
    };
  };
}
