# Writes `mib` MiB of zeros into a memfd that no process maps: the
# memory is charged to the build, but counts toward no task's size, so
# once the slice is out of swap the largest task the OOM killer sees is
# an agent (about 6 MiB) unless agents are exempt. The memfd stays held
# by the builder's fd 3 until it exits, whatever the filler's fate.
{
  python3,
  bash,
  coreutils,
  mib,
}:
derivation {
  name = "tt-slice-shm";
  system = "x86_64-linux";
  builder = builtins.storePath python3 + "/bin/python3";
  args = [
    "-c"
    ''
      import os
      os.dup2(os.memfd_create("fill", 0), 3)
      os.set_inheritable(3, True)
      sh = "${builtins.storePath coreutils}/bin/head -c ${toString mib}M /dev/zero >&3 || echo \"the filler ended with $?\" >&2; echo ok > $out"
      os.execv("${builtins.storePath bash}/bin/bash", ["bash", "-c", sh])
    ''
  ];
}
