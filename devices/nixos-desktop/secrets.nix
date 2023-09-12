{
  sops = {
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      "ssh/ssh_host_rsa_key".path = "/etc/ssh/ssh_host_rsa_key";
      "tailscale/tskey_reusable".path = "/etc/tailscale/tskey-reusable";
    };
  };
}
