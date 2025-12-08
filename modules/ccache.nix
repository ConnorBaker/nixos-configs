{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.ccache;
  nixSettings = config.nix.settings;
in
{
  programs.ccache.enable = true;

  assertions = lib.mkIf cfg.enable [
    {
      assertion = !(nixSettings.auto-allocate-uids or false);
      message = "programs.ccache cannot be enabled when nix.settings.auto-allocate-uids is true";
    }
    {
      assertion = !(lib.elem "auto-allocate-uids" nixSettings.experimental-features);
      message = "programs.ccache cannot be enabled when nix.settings.experimental-features contains auto-allocate-uids";
    }
    {
      assertion = !(lib.elem "uid-range" nixSettings.system-features);
      message = "programs.ccache cannot be enabled when nix.settings.system-features contains uid-range";
    }
  ];

  nix.settings.extra-sandbox-paths = lib.mkIf cfg.enable [
    cfg.cacheDir
  ];

  # A better wrapper than the one upstream:
  # https://github.com/NixOS/nixpkgs/blob/418468ac9527e799809c900eda37cbff999199b6/nixos/modules/programs/ccache.nix#L53-L73
  security.wrappers = lib.mkIf cfg.enable {
    nix-ccache.source = lib.mkForce (
      pkgs.writeShellScript "nix-ccache.sh" ''
        export CCACHE_DIR=${cfg.cacheDir}
        if [ ! -w "$CCACHE_DIR" ]; then
          echo "Directory '$CCACHE_DIR' is not accessible for user $(whoami); please run as root."
          exit 1
        fi
        ${lib.getExe pkgs.ccache} "$@"
      ''
    );
  };
}
