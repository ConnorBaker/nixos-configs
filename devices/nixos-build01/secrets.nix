{config, ...}: {
  sops = {
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      "ssh/id_${config.networking.hostName}_nix_ed25519".path = "/etc/ssh/id_${config.networking.hostName}_nix_ed25519";
      "ssh/ssh_host_rsa_key".path = "/etc/ssh/ssh_host_rsa_key";
      "tailscale/tskey_reusable".path = "/etc/tailscale/tskey-reusable";
    };
  };
}
