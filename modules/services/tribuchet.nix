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
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
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
