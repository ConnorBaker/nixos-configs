{
  sops = {
    # TODO: Switch to /persist/etc when moving to impermanence.
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = ./secrets.yaml;
    gnupg.sshKeyPaths = [];
    secrets = {
      "ssh/ssh_host_rsa_key".path = "/etc/ssh/ssh_host_rsa_key";
      "tailscale/tskey_reusable".path = "/etc/tailscale/tskey-reusable";
    };
  };
}
