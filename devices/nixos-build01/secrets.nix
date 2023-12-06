{
  sops = {
    age.sshKeyPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = ./secrets.yaml;
    gnupg.sshKeyPaths = [];
    secrets =
      let
        # Named after their paths in secrets.yaml.
        tsKey = "tailscale/tskey-reusable";
        # hciKey = "hercules-ci-agent/secrets/cluster-join-token.key";
        # hciBinaryCaches = "hercules-ci-agent/secrets/binary-caches.json";
      in
      {
        ${tsKey}.path = "/etc/${tsKey}";
        # ${hciKey} = {
        #   owner = "hercules-ci-agent";
        #   mode = "0440";
        #   path = "/var/lib/${hciKey}";
        # };
        # ${hciBinaryCaches} = {
        #   owner = "hercules-ci-agent";
        #   mode = "0440";
        #   path = "/var/lib/${hciBinaryCaches}";
        # };
      };
  };
}
