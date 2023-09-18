{
  lib,
  pkgs,
  ...
}: {
  # NOTE: Use mkOptionDefault to ensure our value is added to the list of
  # values, rather than replacing the list of values.
  # Required for various dot-net tools.
  programs.nix-ld.libraries = lib.mkOptionDefault [pkgs.icu.out];

  users.users.connorbaker.packages = with pkgs;
  # Rust unix tools
    [
      bat
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
      dig
      direnv
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
      nix-direnv
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
