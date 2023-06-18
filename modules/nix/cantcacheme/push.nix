{
  config,
  lib,
  pkgs,
  ...
}: {
  nix.settings.secret-key-files = [config.sops.secrets."cantcacheme/signing-key".path];
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
  sops = {
    defaultSopsFile = ../../../secrets/cantcacheme.yaml;
    age.sshKeyPaths = ["/home/connorbaker/.ssh/id_ed25519"];
    secrets = let
      config.restartUnits = ["async-nix-post-build-hook.service"];
    in {
      "cantcacheme/access-key" = config;
      "cantcacheme/s3-endpoint" = config;
      "cantcacheme/secret-access-key" = config;
      "cantcacheme/signing-key" = config;
    };
  };
  systemd.services.async-nix-post-build-hook = {
    environment.XDG_CACHE_HOME = "/tmp/async-nix-post-build-hook";
    unitConfig.After = ["sops-nix.service"];
  };
}
