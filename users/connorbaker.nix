{
  config,
  lib,
  ...
}: {
  programs.git.config = lib.attrsets.optionalAttrs config.programs.git.enable {
    init.defaultBranch = "main";
    user.name = "Connor Baker";
    user.email = "connor.baker@tweag.io";
  };
  users.users.connorbaker = {
    description = "Connor Baker's user account";
    extraGroups = ["wheel"];
    hashedPassword = "$6$I2k4rD4NqxiExXzX$RwvJzZP7mANAC1UEpQKQrI4hhdjUKpx/kUIXUXMO8dLJDW89ICe08Zihw1Eiq0AOZOjkxHxB9kUT3z7gTTnob0";
    isNormalUser = true;
    openssh.authorizedKeys = {
      keyFiles = [
        ../devices/nixos-build01/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-desktop/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-ext/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-orin/keys/ssh_host_ed25519_key.pub
      ];
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXpenPZWADrxK4+6nFmPspmYPPniI3m+3PxAfjbslg+ connorbaker@Connors-MacBook-Pro.local"
      ];
    };
  };
}
