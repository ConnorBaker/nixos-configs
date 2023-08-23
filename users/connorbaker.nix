{
  config,
  lib,
  ...
}: {
  nix.settings.trusted-users = ["connorbaker"];
  programs.git.config = lib.attrsets.optionalAttrs config.programs.git.enable {
    init.defaultBranch = "main";
    user.name = "Connor Baker";
    user.email = "connor.baker@tweag.io";
  };
  users.users = let
    opensshConfig.openssh.authorizedKeys = {
      keyFiles = [
        ../devices/nixos-desktop/keys/id_ed25519.pub
        ../devices/nixos-ext/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-ext/keys/ssh_host_rsa_key.pub
      ];
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXpenPZWADrxK4+6nFmPspmYPPniI3m+3PxAfjbslg+ connorbaker@Connors-MacBook-Pro.local"
      ];
    };
  in {
    root = opensshConfig;
    connorbaker =
      {
        description = "Connor Baker's user account";
        extraGroups = ["wheel"];
        isNormalUser = true;
      }
      // opensshConfig;
  };
}
