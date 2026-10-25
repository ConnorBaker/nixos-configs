{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Use exactly the optimized Nix libraries selected for the running daemon.
  grpc = config.programs.nix-grpc-store.packageSet.default;
  hub = config.services.tribuchet-hub;
  systemctl = "${config.systemd.package}/bin/systemctl";
  # The daemon takes nix's max-jobs at start and again on SIGHUP, never by
  # itself. Only a daemon running this configuration's package handles the
  # signal; an older one still draining after a switch would die of it.
  reread = pkgs.writeShellScript "nix-grpc-daemon-reread" ''
    pid=$(${systemctl} show --property MainPID --value nix-grpc-daemon.service)
    [ "$pid" -gt 0 ] && [ "$(readlink /proc/"$pid"/exe)" = ${lib.getExe' grpc "nix-grpc-daemon"} ] || exit 0
    exec ${systemctl} kill --kill-whom=main --signal=SIGHUP nix-grpc-daemon.service
  '';
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
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 50051 ];

  # Leave a running daemon alone on switch. Upstream's reload is a drain, which
  # assumes other builders take the new builds; each host here is its own
  # scheduler's only builder, so the drain refused every new build until the
  # slowest running one finished (nixos-ext, 2026-10-25 05:37-05:54Z). The new
  # generation starts after --idle-timeout or a deliberate restart.
  systemd.services.nix-grpc-daemon = {
    reloadIfChanged = lib.mkForce false;
    restartIfChanged = false;
  };

  # A switch that changes nix.conf.
  systemd.services.nix-grpc-daemon-nix-conf = {
    description = "Have nix-grpc-daemon read nix.conf's max-jobs again";
    after = [ "nix-grpc-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ config.environment.etc."nix/nix.conf".source ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = reread;
    };
  };
  # On the hub, each rewrite of the max-jobs fragment nix.conf includes, as
  # Tribuchet's own tribuchet-nix-reload does for nix-daemon.
  systemd.paths.nix-grpc-daemon-reread = lib.mkIf (hub.enable && hub.externalBuilders.enable && hub.externalBuilders.dynamic) {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathModified = toString hub.externalBuilders.nixConfigPath;
  };
  systemd.services.nix-grpc-daemon-reread = {
    description = "Have nix-grpc-daemon read nix's max-jobs again";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = reread;
    };
  };
}
