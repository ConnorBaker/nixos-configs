{ lib, ... }:
let
  inherit (lib.options) mkOption;
  inherit (lib.types) nonEmptyStr;
in
{
  imports = [
    ./attic.nix
    ./caddy.nix
    ./postgresql.nix
  ];

  config.services.binary-cache.domain = "cantcache.me";
  options.services.binary-cache.domain = mkOption {
    description = "The name of the binary cache to use";
    type = nonEmptyStr;
  };
}
