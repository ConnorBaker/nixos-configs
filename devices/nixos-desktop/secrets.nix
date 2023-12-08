{
  sops = {
    # TODO: Switch to /persist/etc when moving to impermanence.
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = ./secrets.yaml;
    gnupg.sshKeyPaths = [];
    secrets =
      let
        # Named after their paths in secrets.yaml.
        tsKey = "tailscale/tskey-reusable";
        hciBinaryCaches = "hercules-ci-agent/secrets/binary-caches.json";
        hciClusterKey = "hercules-ci-agent/secrets/cluster-join-token.key";
        hciSessionKey = "hercules-ci-agent/secretState/session.key";
      in
      {
        ${tsKey}.path = "/etc/${tsKey}";
        ${hciBinaryCaches} = {
          owner = "hercules-ci-agent";
          mode = "0440";
          path = "/var/lib/${hciBinaryCaches}";
        };
        ${hciClusterKey} = {
          owner = "hercules-ci-agent";
          mode = "0440";
          path = "/var/lib/${hciClusterKey}";
        };
        ${hciSessionKey} = {
          owner = "hercules-ci-agent";
          mode = "0440";
          path = "/var/lib/${hciSessionKey}";
        };
      };
  };
}
