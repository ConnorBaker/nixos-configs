{ config, lib, ... }:
let
  # Named after their paths in secrets.yaml.
  tsKey = "tailscale/tskey-reusable";
  tsSecrets.${tsKey}.path = "/etc/${tsKey}";

  # Ensure that the user name is not changed.
  hciUser =
    let
      inherit (config.users.users.hercules-ci-agent) name;
      expectedName = "hercules-ci-agent";
    in
    assert lib.asserts.assertMsg (name == expectedName) "${expectedName} user name changed to ${name}!";
    name;
  hciSecrets =
    let
      hciSecretPaths = builtins.map (relativeSecretPath: "${hciUser}/${relativeSecretPath}") [
        "secrets/binary-caches.json"
        "secrets/cluster-join-token.key"
        "secretState/session.key"
        "secrets/secrets.json"
      ];
    in
    lib.attrsets.genAttrs hciSecretPaths (name: {
      owner = hciUser;
      mode = "0440";
      path = "/var/lib/${name}";
    });
in
{
  sops = {
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ./secrets.yaml;
    gnupg.sshKeyPaths = [ ];
    secrets = tsSecrets // hciSecrets;
  };
}
