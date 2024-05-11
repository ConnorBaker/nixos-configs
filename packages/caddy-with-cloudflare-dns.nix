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
  version = "2.8.0-beta.2";
  rev = "dd203ad41f15872939e327f0b399366cb13f2287";
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

          plugins = [ "github.com/caddy-dns/cloudflare@44030f9306f4815aceed3b042c7f3d2c2b110c97" ];

          configurePhase = ''
            export GOCACHE=$TMPDIR/go-cache
            export GOPATH="$TMPDIR/go"
            export XCADDY_SKIP_BUILD=1
          '';

          buildPhase = ''
            ${xcaddy}/bin/xcaddy build "${rev}" ${
              lib.concatMapStringsSep " " (plugin: "--with ${plugin}") finalAttrs.plugins
            }
            cd buildenv*
            go mod vendor
          '';

          installPhase = ''
            cp -a . $out
          '';

          outputHash = "sha256-IywStWtGmMV5/yvbDvjGkAdANPk4tLG13RP0I1Tla/8=";
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
