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
    isNormalUser = true;
    hashedPassword = "$6$ofrQUy4vgmA5ufyE$2/3o.j5ZZ2DKZ2O7yJ3FBFvk3y9noN3iovTfyudDDAcY579oyQWhfqkXaPPUlrORRNSnhzeVSUJad0bpy65p.0";
    openssh.authorizedKeys = {
      keyFiles = [
        ../devices/nixos-desktop/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-ext/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-build01/keys/ssh_host_ed25519_key.pub
      ];
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXpenPZWADrxK4+6nFmPspmYPPniI3m+3PxAfjbslg+ connorbaker@Connors-MacBook-Pro.local"
      ];
    };
  };
}
