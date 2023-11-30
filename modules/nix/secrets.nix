{config, ...}:
{
  sops.secrets."ssh/id_nix_ed25519" = {
    owner = config.users.users.nix.name;
    mode = "0400";
    path = "/etc/ssh/id_nix_ed25519";
    sopsFile = ./secrets.yaml;
  };
}
