{ config, ... }:
let
  # Use exactly the optimized Nix libraries selected for the running daemon.
  grpc = config.programs.nix-grpc-store.packageSet.default;
in
{
  programs.nix-grpc-store = {
    enable = true;
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
}
