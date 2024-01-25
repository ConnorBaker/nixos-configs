{ config, ... }:
builtins.throw "This module does not currently work as desired." {
  nixpkgs.overlays = [
    (_: prev: {
      ccache = prev.ccache.overrideAttrs (
        oldAttrs: {
          postInstall =
            (oldAttrs.postInstall or "")
            + ''
              mkdir -p $out/etc
              cat > $out/etc/ccache.conf <<EOF
              base_dir = $NIX_BUILD_TOP
              compiler_check = content
              compression = true
              cache_dir = /var/cache/ccache
              max_size = 1T
              run_second_cpp = false
              depend_mode = false
              direct_mode = false
              hash_dir = false
              inode_cache = false
              sloppiness = include_file_ctime,include_file_mtime,time_macros,pch_defines,random_seed
              umask = 007
              EOF
            '';
        }
      );
    })
  ];
  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];
  programs.ccache = {
    # TODO: We should be able to set additional settings here, like cache size or compression algorithm, etc...
    # Although, I guess we can set that through the environment configuration file? Can ccache access that? Is that impure?
    enable = true;
    cacheDir = "/var/cache/ccache";
    # Must have at least one package name for ccacheWrapper to be set
    # Add every package in pkgs which is not a bootstrap package
    packageNames = [
      "nix"
      "python3"
    ];
  };
}
