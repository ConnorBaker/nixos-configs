{
  config,
  lib,
  pkgs,
  ...
}:
{
  # NOTE: Use mkOptionDefault to ensure our value is added to the list of
  # values, rather than replacing the list of values.
  # Required for various dot-net tools.
  programs.nix-ld.libraries = lib.mkOptionDefault [
    config.hardware.nvidia.package
    pkgs.icu.out
  ];

  users.users.connorbaker.packages =
    # Python
    [
      pkgs.black
      pkgs.ruff
    ]
    # C/C++
    ++ [
      pkgs.cmake
      pkgs.dotnet-runtime # for CMake LSP in VS Code
    ]
    # Misc tools
    ++ [
      pkgs.direnv
      pkgs.docker-compose
      pkgs.nvitop
    ]
    # Shell
    ++ [
      pkgs.shellcheck
      pkgs.shfmt
    ]
    # Nix
    ++ [
      pkgs.nil
      pkgs.nix-direnv
      pkgs.nix-eval-jobs
      pkgs.nix-output-monitor
      pkgs.nixfmt-rfc-style
      pkgs.nixpkgs-review
    ];
}
