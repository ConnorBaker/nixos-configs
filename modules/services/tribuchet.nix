{
  config,
  lib,
  pkgs,
  nixOptimization,
  ...
}:
let
  isHub = config.networking.hostName == "nixos-ext";
  # This package includes automatic Tarmac evaluation, PGO, and the ported
  # Tribuchet patches. Its wrappers preserve separately configured plugins.
  patchedNix = nixOptimization.packages.${pkgs.stdenv.hostPlatform.system}.tarmac-pgo;
in
{
  services.tribuchet-hub = lib.mkIf isHub {
    enable = true;
    openFirewall = false;
    externalBuilders = {
      enable = true;
      systems = [ "x86_64-linux" ];
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

  nix.package = lib.mkIf (!isHub) patchedNix;
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf isHub [ 7437 ];

  systemd.services.tribuchet-worker = {
    after = [ "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled-autoconnect.service" ];
  };
}
