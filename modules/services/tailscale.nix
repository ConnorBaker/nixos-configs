{
  config,
  lib,
  pkgs,
  ...
}: {
  networking.firewall = {
    enable = true;
    trustedInterfaces = ["tailscale0"];
    allowedUDPPorts = [config.services.tailscale.port];
  };
  services.tailscale.enable = true;
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";

    # make sure tailscale is running before trying to connect to tailscale
    after = ["network-pre.target" "tailscale.service"];
    wants = ["network-pre.target" "tailscale.service"];
    wantedBy = ["multi-user.target"];

    # set this service as a oneshot job
    serviceConfig.Type = "oneshot";

    # have the job run this shell script
    script =
      # wait for tailscaled to settle
      ''
        echo "Waiting for tailscale.service start completion ..."
        sleep 5
      ''
      # check if already authenticated
      + ''
        echo "Checking if already authenticated to Tailscale ..."
        status="$(${lib.getExe pkgs.tailscale} status -json | ${lib.getExe pkgs.jq} -r .BackendState)"
        echo "Tailscale status: $status"
        if [ $status = "Running" ]; then
          echo "Already authenticated to Tailscale, exiting."
          exit 0
        fi
      ''
      # otherwise authenticate with tailscale
      # limit to 30s to avoid hanging the boot process
      + ''
        echo "Authenticating with Tailscale ..."
        ${pkgs.coreutils}/bin/timeout 30 \
          ${lib.getExe pkgs.tailscale} up --auth-key file:/etc/tailscale/tskey-reusable
      '';
  };
}
