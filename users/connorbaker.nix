{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../modules/programs/git.nix
    ../modules/programs/htop.nix
    ../modules/programs/nix-ld.nix
  ];
  programs.git.config = lib.attrsets.optionalAttrs config.programs.git.enable {
    init.defaultBranch = "main";
    user.name = "Connor Baker";
    user.email = "connor.baker@tweag.io";
  };
  users.users.connorbaker = {
    description = "Connor Baker's user account";
    extraGroups = [ "wheel" ] ++ lib.optionals config.virtualisation.docker.enable [ "docker" ];
    hashedPassword = "$y$j9T$ElNzp8jVQBLw00WZda/PR/$ilWJEMkkGBjYPEG.IkiNGp7ngsLgI7hGzsMeyywNYJ.";
    isNormalUser = true;
    openssh.authorizedKeys = {
      keyFiles = [
        ../devices/eu.nixbuild.net/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-build01/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-desktop/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-ext/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-orin/keys/ssh_host_ed25519_key.pub
        ../devices/ubuntu-hetzner/keys/ssh_host_ed25519_key.pub
        ../devices/ubuntu-orin/keys/ssh_host_ed25519_key.pub
      ];
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXpenPZWADrxK4+6nFmPspmYPPniI3m+3PxAfjbslg+ connorbaker@Connors-MacBook-Pro.local"
      ];
    };
    packages =
      [ pkgs.attic ]
      # Rust unix tools
      ++ [
        pkgs.bat
        pkgs.histodu
        pkgs.hyperfine
        pkgs.ripgrep
      ]
      # Utilities
      ++ [
        pkgs.dig
        pkgs.gh
        pkgs.git
        pkgs.htop
        pkgs.jq
        pkgs.tmux
        pkgs.vim
      ]
      # Sops tools
      ++ [
        pkgs.age
        pkgs.sops
        pkgs.ssh-to-age
      ];
  };
}
