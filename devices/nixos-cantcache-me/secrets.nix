let
  # Named after their paths in secrets.yaml.
  tsKey = "tailscale/tskey-reusable";
in
{
  sops = {
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ./secrets.yaml;
    gnupg.sshKeyPaths = [ ];
    secrets.${tsKey}.path = "/etc/${tsKey}";
  };
}
