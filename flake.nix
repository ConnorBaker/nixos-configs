{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.queued-build-hook.url = "github:nix-community/queued-build-hook";
  outputs = {
    self,
    nixpkgs,
    queued-build-hook,
  }: {
    nixosConfigurations.nixos-desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./modules/nixos-desktop
        queued-build-hook.nixosModules.queued-build-hook
        ({
          lib,
          pkgs,
          ...
        }: {
          queued-build-hook = {
            enable = true;
            postBuildScriptContent = ''
              set -euo pipefail
              set -f # disable globbing
              export IFS=' '

              echo "Uploading paths" $OUT_PATHS
              exec ${lib.getExe pkgs.nix} copy \
                --extra-secret-key-files ''${CREDENTIALS_DIRECTORY}/cantcacheme-signing-key \
                --to "s3://cant-cache-me?endpoint=$CANTCACHEME_S3_ENDPOINT&compression=zstd&compression-level=19" \
                $OUT_PATHS
            '';
            credentials = {
              AWS_ACCESS_KEY_ID = "/run/keys/cantcacheme-access-key";
              AWS_SECRET_ACCESS_KEY = "/run/keys/cantcacheme-secret-access-key";
              CANTCACHEME_S3_ENDPOINT = "/run/keys/cantcacheme-s3-endpoint";
              cantcacheme-signing-key = "/run/keys/cantcacheme-signing-key";
            };
          };
        })
      ];
    };
  };
}

