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
      packages = with pkgs;
      # Rust unix tools
        [
          bat
          exa
          ripgrep
        ]
        # Python
        ++ [
          black
          (python3.withPackages (ps: with ps; [pydantic requests typing-extensions]))
          ruff
        ]
        # C/C++
        ++ [
          cmake
          dotnet-runtime # for CMake LSP in VS Code
        ]
        # Misc tools
        ++ [
          gh
          git
          htop
          jq
          nvitop
          vim
        ]
        # Nix
        ++ [
          alejandra
          nil
          nix-output-monitor
          nixpkgs-review
        ]
        # Sops tools
        ++ [
          age
          sops
          ssh-to-age
        ];
    };
  };
}
