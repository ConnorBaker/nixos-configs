# A host's nix.package, run under another generation's nix.conf (as when
# nixos-rebuild runs the next generation's Nix before activation), loads its
# own generation's plugin-files and none of that nix.conf's, even when its
# own list is empty: here the previous generation's plugin is a file no Nix
# can load, which Nix refuses fatally. nix-grpc-store's grpc-linger is a
# setting only its loaded plugin registers. nix-env (which the boot loader
# installer runs) goes through the same wrappers as nix.
{
  lib,
  runCommand,
  hostConfig,
}:
let
  nix = hostConfig.nix.package;
  plugins = hostConfig.nix.settings.plugin-files;
in
runCommand "generation-plugins" { } ''
  mkdir -p conf previous
  echo 'not a plugin' > previous/plugin.so
  echo "plugin-files = $PWD/previous" > conf/nix.conf
  export HOME=$TMPDIR NIX_CONF_DIR=$PWD/conf
  show() {
    ${nix}/bin/nix --extra-experimental-features nix-command config show "$1" 2>>stderr.log ||
      { cat stderr.log >&2; exit 1; }
  }

  shown=$(show plugin-files)
  echo "plugin-files: $shown"
  for plugin in ${lib.escapeShellArgs plugins}; do
    [[ " $shown " == *" $plugin "* ]]
  done
  if [[ " $shown " == *" $PWD/previous "* ]]; then
    echo "the previous generation's plugin-files are in effect"; exit 1
  fi
  ${lib.optionalString (builtins.elem "${hostConfig.programs.nix-grpc-store.package}/lib/nix/plugins" plugins) ''
    test "$(show grpc-linger)" = 0
  ''}
  ${nix}/bin/nix-env --version 2>>stderr.log | grep '^nix-env (Nix) '
  cat stderr.log
  touch $out
''
