{
  imports = [ ../../modules/secrets.nix ];
  sops.defaultSopsFile = ./secrets.yaml;
}
