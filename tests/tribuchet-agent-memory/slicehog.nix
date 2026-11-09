# Holds `mib` MiB of random bytes, which zram cannot store in less, in
# the buffer of `tail -n 1` (the input has no newline). With `child`
# the builder outlives the filler and ignores how it ended: it succeeds
# however that went, as builds whose child was OOM-killed did. Without
# it the builder fails when the filler does (`tail`, the pipeline's
# status: `head` ending early stops `tr` with a broken pipe).
{
  bash,
  coreutils,
  name,
  mib,
  child ? false,
}:
let
  bin = builtins.storePath coreutils + "/bin";
  fill = "${bin}/tr -d '\\n' </dev/urandom | ${bin}/head -c ${toString mib}M | ${bin}/tail -n 1 >/dev/null";
in
derivation {
  name = "tt-slice-${name}";
  system = "x86_64-linux";
  builder = builtins.storePath bash + "/bin/bash";
  args = [
    "-c"
    (
      if child then
        ''
          ${fill} || echo "the filler ended with $?" >&2
          echo ok > $out
        ''
      else
        ''
          set -e
          ${fill}
          echo ok > $out
        ''
    )
  ];
}
