{
  sops = {
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ];
    secrets."tailscale/tskey-reusable".path = "/etc/tailscale/tskey-reusable";
  };
}
