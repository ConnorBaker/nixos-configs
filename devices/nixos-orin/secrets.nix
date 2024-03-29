{
  sops = {
    # TODO: Switch to /persist/etc when moving to impermanence.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ./secrets.yaml;
    gnupg.sshKeyPaths = [ ];
    secrets =
      let
        name = "tailscale/tskey-reusable";
      in
      {
        ${name}.path = "/etc/${name}";
      };
  };
}
