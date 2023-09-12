{
  sops.secrets."ssh/id_nix_ed25519" = {
    path = "/etc/ssh/id_nix_ed25519";
    sopsFile = ./secrets.yaml;
  };
}
