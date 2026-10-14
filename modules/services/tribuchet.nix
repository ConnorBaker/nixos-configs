{ config, lib, ... }:
let
  isHub = config.networking.hostName == "nixos-ext";
in
{
  services.tribuchet-hub = lib.mkIf isHub {
    enable = true;
    openFirewall = false;
    settings = {
      auth = "tailscale";
      tailscale-allowed-tags = [ "tag:ci" ];
    };
  };

  services.tribuchet-worker = {
    enable = true;
    agents = 3;
    settings = {
      auth = "tailscale";
      hub = "http://nixos-ext.rove-hexatonic.ts.net:7437";
      max-jobs = 3;
    };
  };

  # External execution needs patches in the selected Nix package before
  # enabling services.tribuchet-hub.externalBuilders.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf isHub [ 7437 ];

  systemd.services.tribuchet-worker = {
    after = [ "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled-autoconnect.service" ];
  };
}
