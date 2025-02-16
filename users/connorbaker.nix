{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.modules) mkIf mkMerge;
in
{
  imports = [
    ../modules/programs/git.nix
    ../modules/programs/htop.nix
    ../modules/programs/nix-ld.nix
  ];

  # For explainshell and iperf
  networking.firewall = {
    allowedTCPPorts = [
      5000
      5001
    ];
    allowedUDPPorts = [
      5000
      5001
    ];
  };

  programs.git.config = mkIf config.programs.git.enable {
    init.defaultBranch = "main";
    user.name = "Connor Baker";
    user.email = "ConnorBaker01@gmail.com";
  };
  users.users.connorbaker = {
    description = "Connor Baker's user account";
    extraGroups = mkMerge [
      [ "wheel" ]
      (mkIf config.virtualisation.docker.enable [ "docker" ])
    ];
    hashedPassword = "$y$j9T$ElNzp8jVQBLw00WZda/PR/$ilWJEMkkGBjYPEG.IkiNGp7ngsLgI7hGzsMeyywNYJ.";
    isNormalUser = true;
    openssh.authorizedKeys = {
      keyFiles = [
        ../devices/nixos-build01/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-desktop/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-ext/keys/ssh_host_ed25519_key.pub
      ];
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXpenPZWADrxK4+6nFmPspmYPPniI3m+3PxAfjbslg+ connorbaker@Connors-MacBook-Pro.local"
      ];
    };
    packages =
      # Rust unix tools
      [
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
        pkgs.iperf
        pkgs.jq
        pkgs.micromamba
        pkgs.parallel-full
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
