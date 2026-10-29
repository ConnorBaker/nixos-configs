# nix-daemon's pre-build hook (modules/nix/fixed-output-gate.nix, and
# spark-nix-infra's nix.custom.conf): fails every sandboxed local build Nix
# would give the network, then runs `next`, the hook it replaces.
{
  lib,
  writeShellApplication,
  next ? null,
}:
writeShellApplication {
  name = "refuse-local-fixed-output";
  text = ''
    # Nix passes the .drv and the build's chroot. Before running this hook
    # it writes the chroot's /etc/hosts, but only for a build it isolates
    # from the network (setupBuildChroot, libstore/unix/build/chroot.cc):
    # fixed-output and impure derivations get none. That holds even when the
    # .drv is not in this store, as when a CLI with its own evaluation store
    # (Tarmac) builds in-process.
    if [ "$#" -lt 2 ] || [ -z "$2" ] || [ ! -e "$2/etc/hosts" ]; then
      echo "refuse-local-fixed-output: ''${1:-?} would build with this host's network, so only on Tribuchet" >&2
      exit 1
    fi
  ''
  + lib.optionalString (next != null) ''
    exec ${next} "$@"
  '';
}
