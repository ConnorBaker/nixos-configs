# Vendored from https://github.com/NixOS/nixpkgs/pull/259275
# https://github.com/emilylange/nixos-config/blob/8206578f5c1281b36c6fb120405edcf17da472fe/packages/caddy/default.nix
# Updated to v2.8.0-beta.2, added cloudflare dns plugin, formatted with nixfmt, and removed `rec`
{
  lib,
  caddy,
  xcaddy,
  buildGoModule,
  stdenv,
  cacert,
  go,
}:
let
  version = "2.8.4";
  rev = "7088605cc11c52c2777ab613dfc5c2a9816006e4";
in
caddy.override {
  buildGoModule =
    args:
    buildGoModule (
      args
      // {
        src = stdenv.mkDerivation (finalAttrs: {
          pname = "caddy-using-xcaddy-${xcaddy.version}";
          inherit version;

          dontUnpack = true;
          dontFixup = true;

          nativeBuildInputs = [
            cacert
            go
          ];

          plugins = [ "github.com/caddy-dns/cloudflare@d11ac0bfeab7475d8b89e2dc93f8c7a8b8859b8f" ];

          configurePhase = ''
            export GOCACHE=$TMPDIR/go-cache
            export GOPATH="$TMPDIR/go"
            export XCADDY_SKIP_BUILD=1
          '';

          buildPhase = ''
            ${lib.getExe xcaddy} build "${rev}" ${
              lib.concatMapStringsSep " " (plugin: "--with ${plugin}") finalAttrs.plugins
            }
            cd buildenv*
            go mod vendor
          '';

          installPhase = ''
            cp -a . $out
          '';

          outputHash = "sha256-8T1pBYVRytMa0kItYfFQJpj5CtXaIT8P2UWdh7b1gEc=";
          outputHashMode = "recursive";
        });

        subPackages = [ "." ];
        ldflags = [
          "-s"
          "-w"
        ];
        inherit version;
        vendorHash = null;
      }
    );
}
