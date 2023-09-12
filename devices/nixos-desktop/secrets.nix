{
  sops = {
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = ./secrets.yaml;
    secrets."tailscale/tskey_reusable".path = "/etc/tailscale/tskey-reusable";
  };
}
