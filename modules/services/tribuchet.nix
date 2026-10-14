{
  config,
  lib,
  patchedNix,
  ...
}:
let
  isHub = config.networking.hostName == "nixos-ext";
in
{
  imports = [ ./nix-grpc-store.nix ];
  services.tribuchet-hub = lib.mkIf isHub {
    enable = true;
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
      nixPackage = patchedNix;
      patchNix = false;
    };
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
      recursive-nix = true;
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf isHub [ 7437 ];

  systemd.services.tribuchet-worker = {
    after = [ "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled-autoconnect.service" ];
  };
}
