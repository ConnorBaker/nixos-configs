let
  # Named after their paths in secrets.yaml.
  tsKey = "tailscale/tskey-reusable";
  tsSecrets.${tsKey}.path = "/etc/${tsKey}";
in
{
  sops = {
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ./secrets.yaml;
    gnupg.sshKeyPaths = [ ];
    secrets = tsSecrets;
  };
}
