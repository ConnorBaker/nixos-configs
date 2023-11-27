{
  config,
  lib,
  pkgs,
  ...
}:
{
  nix.settings.secret-key-files = [ config.sops.secrets."cantcacheme/signing-key".path ];
  queued-build-hook = {
    enable = true;
    postBuildScriptContent = ''
      set -euo pipefail
      set -f # disable globbing
      export IFS=' '

      echo "Uploading paths" $OUT_PATHS
      exec ${lib.getExe pkgs.nix} copy \
        --to "s3://cant-cache-me?endpoint=$CANTCACHEME_S3_ENDPOINT&compression=zstd&compression-level=19" \
        $OUT_PATHS
    '';
    credentials = {
      AWS_ACCESS_KEY_ID = config.sops.secrets."cantcacheme/access-key".path;
      AWS_SECRET_ACCESS_KEY = config.sops.secrets."cantcacheme/secret-access-key".path;
      CANTCACHEME_S3_ENDPOINT = config.sops.secrets."cantcacheme/s3-endpoint".path;
    };
  };
  sops.secrets =
    lib.attrsets.genAttrs
      [
        "cantcacheme/access-key"
        "cantcacheme/s3-endpoint"
        "cantcacheme/secret-access-key"
        "cantcacheme/signing-key"
      ]
      (
        lib.trivial.const {
          restartUnits = [
            "async-nix-post-build-hook.service"
            "async-nix-post-build-hook.socket"
          ];
          sopsFile = ./secrets/cantcacheme.yaml;
        }
      );
  systemd.services.async-nix-post-build-hook = {
    environment.HOME = "/var/lib/async-nix-post-build-hook";
    serviceConfig.StateDirectory = "async-nix-post-build-hook";
    # Because the hook runs as root, there's no need for the following line.
    # serviceConfig.SupplementaryGroups = [config.users.groups.keys.name];
    unitConfig.After = [ "sops-nix.service" ];
  };
}
