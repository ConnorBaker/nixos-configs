{pkgs, ...}: {
  users.users.connorbaker.packages = with pkgs;
  # Rust unix tools
    [
      bat
      exa
      ripgrep
    ]
    # Python
    ++ [
      black
      ruff
    ]
    # C/C++
    ++ [
      cmake
      dotnet-runtime # for CMake LSP in VS Code
    ]
    # Misc tools
    ++ [
      azure-cli
      gh
      git
      htop
      jq
      nvitop
      tmux
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
}
