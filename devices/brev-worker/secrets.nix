{ lib, ... }:
{
  imports = [ ../../modules/secrets.nix ];
  sops.defaultSopsFile = ./secrets.yaml;
  # modules/nix/secrets.yaml is encrypted to the four existing hosts only.
  # The Brev instances carry their own key there, which nothing authorizes;
  # adding it to that file needs one of those hosts to decrypt it.
  sops.secrets."ssh/id_nix_ed25519".sopsFile = lib.mkForce ./secrets.yaml;
}
