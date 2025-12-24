{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.modules) mkIf;
in
{
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

  programs = {
    git = {
      enable = true;
      config = {
        init.defaultBranch = "main";
        user.name = "Connor Baker";
        user.email = "ConnorBaker01@gmail.com";
      };
    };

    htop = {
      enable = true;
      settings = {
        column_meter_modes_0 = [
          1
          2
          2
          2
        ];
        column_meter_modes_1 = [
          1
          2
          2
          2
        ];
        column_meters_0 = [
          "LeftCPUs4"
          "Memory"
          "Zram"
          "NetworkIO"
        ];
        column_meters_1 = [
          "RightCPUs4"
          "DiskIO"
          "ZFSARC"
          "ZFSCARC"
        ];
        header_layout = "two_50_50";
        show_cpu_frequency = 1;
        show_cpu_temperature = 1;
      };
    };

    nix-ld.enable = true;
  };

  users.users.connorbaker = {
    description = "Connor Baker's user account";
    extraGroups = [
      "wheel"
      (mkIf config.virtualisation.docker.enable "docker")
    ];
    hashedPassword = "$y$j9T$ElNzp8jVQBLw00WZda/PR/$ilWJEMkkGBjYPEG.IkiNGp7ngsLgI7hGzsMeyywNYJ.";
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
    packages = [
      # C/C++
      pkgs.cmake
      pkgs.dotnet-runtime # for CMake LSP in VS Code

      # Nix
      pkgs.nil
      pkgs.nix-direnv
      pkgs.nix-eval-jobs
      pkgs.nix-output-monitor
      pkgs.nixfmt-rfc-style
      pkgs.nixpkgs-review

      # Node
      pkgs.nodePackages_latest.nodejs
      pkgs.pnpm

      # Python
      pkgs.ruff
      pkgs.uv

      # Rust unix tools
      pkgs.histodu
      pkgs.hyperfine
      pkgs.ripgrep

      # Shell
      pkgs.shellcheck
      pkgs.shfmt

      # Sops tools
      pkgs.age
      pkgs.sops
      pkgs.ssh-to-age

      # Utilities
      pkgs.dig
      pkgs.direnv
      pkgs.docker-compose
      pkgs.gh
      pkgs.git
      pkgs.htop
      pkgs.iperf
      pkgs.jq
      pkgs.micromamba
      pkgs.patchelf
      pkgs.parallel-full
      pkgs.perf
      pkgs.tmux
      pkgs.vim
      (mkIf config.hardware.nvidia.enabled pkgs.nvitop)
    ];
  };
}
