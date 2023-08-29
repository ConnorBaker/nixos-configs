{config, ...}: {
  nix.settings.extra-sandbox-paths = [config.programs.ccache.cacheDir];
  programs.ccache = {
    enable = true;
    cacheDir = "/var/cache/ccache";
    # Must have at least one package name for ccacheWrapper to be set
    packageNames = ["nix"];
  };
}
