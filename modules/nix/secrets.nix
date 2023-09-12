{
  sops.secrets."ssh/id_nix_ed25519" = {
    owner = "nix";
    path = "/etc/ssh/id_nix_ed25519";
    sopsFile = ./secrets.yaml;
  };
}
