# A build whose memory slicefill.py (`script`, a store path) shapes:
# `hold` MiB of `mode` pages (it succeeds if it keeps them), or `grow`
# without end (a runaway).
{
  python3,
  script,
  name,
  what,
  mode,
  mib ? null,
}:
derivation {
  name = "tt-slice-${name}";
  system = "x86_64-linux";
  builder = builtins.storePath python3 + "/bin/python3";
  args = [
    "-I"
    (builtins.storePath script)
    what
    mode
  ]
  ++ (if mib == null then [ ] else [ (toString mib) ]);
}
