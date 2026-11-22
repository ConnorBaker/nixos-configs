# A generation's Nix loads that generation's plugin-files, not those of the
# nix.conf it finds. /etc/nix/nix.conf is the running generation's, and the
# next generation's Nix runs before activation replaces it: nixos-rebuild
# re-executes into the next generation's nixos-rebuild, which runs that
# generation's nix.package, and switch-to-configuration's boot loader
# installer runs its nix-env. Reading the previous generation's
# plugin-files, it opens plugins built for the previous Nix, which a Nix of
# the same version need not be able to load: on 2026-11-21 the nix-grpc-store
# plugin built for Nix 602cd88 failed to load in Nix ba52427 (both 2.36.0),
# and every remote build of that switch was refused.
#
# So nix.package carries its generation's list: a plain assignment appended
# to NIX_CONFIG, which Nix applies after nix.conf and which the build hook
# and every other nix it starts inherit. It replaces any plugin-files or
# extra-plugin-files the user's nix.conf or the caller's NIX_CONFIG names
# too, in every invocation of these commands and in the nix shell and
# nix develop environments they start, as Tarmac's wrapper (inside this one,
# nix-optimization's tarmac-wrapper-init.nix) selects its own loader.
# nix-daemon does not go through it: its unit (from the package) runs the
# unwrapped binary, which the switch restarts after the new nix.conf is in
# place. The Tribuchet hub sets nix.package itself, to its
# externalBuilders.nixPackage, which modules/services/tribuchet.nix sets to
# this same package.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs) nix;
  pluginFiles = config.nix.settings.plugin-files or [ ];
in
{
  nix.package = lib.mkDefault config.system.build.nixWithGenerationPlugins;
  # Even an empty list: a generation without plugins loads none of the
  # previous generation's either.
  system.build.nixWithGenerationPlugins = pkgs.symlinkJoin {
    name = "${nix.name}-with-generation-plugins";
    paths = [ nix ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    # Each command keeps its own wrapper underneath, which fixes argv[0]
    # (nix-env, nix-store, ...) for the nix binary they all are. The new
    # wrapper replaces the symlink to it, not the file it points to.
    postBuild = ''
      for executable in "$out"/bin/*; do
        name=$(basename "$executable")
        makeBinaryWrapper ${nix}/bin/"$name" "$TMPDIR/$name" \
          --suffix NIX_CONFIG $'\n' ${lib.escapeShellArg "plugin-files = ${toString pluginFiles}"}
        mv -f "$TMPDIR/$name" "$executable"
      done
    '';
    passthru = {
      inherit (nix)
        pname
        version
        libs
        components
        plugin
        unwrapped
        ;
    };
    inherit (nix) meta;
  };
}
