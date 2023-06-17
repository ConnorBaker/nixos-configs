{
  config,
  lib,
  pkgs,
  ...
}: {
  nix.settings.trusted-users = ["connorbaker"];
  programs.git.config = lib.attrsets.optionalAttrs config.programs.git.enable {
    init.defaultBranch = "main";
    user.name = "Connor Baker";
    user.email = "connor.baker@tweag.io";
  };
  users.users = {
    connorbaker = {
      description = "Connor Baker's user account";
      extraGroups = ["wheel"];
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXpenPZWADrxK4+6nFmPspmYPPniI3m+3PxAfjbslg+ connorbaker@Connors-MacBook-Pro.local"
      ];
      packages = with pkgs; [
        bat
        black
        exa
        gh
        git
        htop
        jq
        nil
        nixpkgs-review
        python3
        ripgrep
        ruff
        vim
      ];
    };
  };
}
