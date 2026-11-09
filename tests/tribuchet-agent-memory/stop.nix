# NixOS VM test: tribuchet-agent-swap stopped while its start runs, as
# many times as fit in 140 s on each of two nodes (node.nix's). The
# hostile case: a stop 0-79 ms after a start that does not wait.
# systemd 261.3 kills a start it is told to stop and skips ExecStop
# (service.c:3544-3555); with the cleanup there, 9 of 800 such stops
# left the slice S with the unit down. After every stop the slice's
# MemorySwapMax and memory.swap.max must be 0 and zswap off. Each
# iteration is shown by its delay, the unit's state and result and its
# InvocationID. Then the stop as built,
# its call for 0 failing: S may still be in force, so zswap stays on.
# The loop writes its row count and the file's sha256 last, and the rows
# come out as a file, not through the driver's shell: a row lost or
# garbled on the way (one run read 255 of 400 rows through the shell,
# two spliced) fails the check, as does any row out of place.
{ tribuchet, nixosModule }:
{
  pkgs,
  lib,
  nodes,
  ...
}:
let
  mib = 1024 * 1024;
  am = import ./node.nix {
    inherit
      tribuchet
      nixosModule
      pkgs
      lib
      ;
  };
  slice = "system-tribuchet\\x2dagent.slice";
  cg = "/sys/fs/cgroup/system.slice/${slice}";
  loop = pkgs.writeShellScript "stop-start-loop" ''
    set -u
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.systemd
      ]
    }
    n=$1 budget=$2 out=$3
    slice='${slice}'
    t0=$SECONDS rows=0
    for i in $(seq 1 "$n"); do
      if [ $((SECONDS - t0)) -ge "$budget" ]; then break; fi
      systemctl reset-failed tribuchet-agent-swap 2>/dev/null
      d=$((RANDOM % 80))
      systemctl start --no-block tribuchet-agent-swap
      sleep "0.$(printf %03d "$d")"
      systemctl stop tribuchet-agent-swap
      st=$(systemctl show -P ActiveState tribuchet-agent-swap)
      res=$(systemctl show -P Result tribuchet-agent-swap)
      id=$(systemctl show -P InvocationID tribuchet-agent-swap)
      conf=$(systemctl show -P MemorySwapMax "$slice")
      read -r cur <'${cg}/memory.swap.max'
      read -r z </sys/module/zswap/parameters/enabled
      echo "$i $d $st $res $conf $cur $z $id" >>"$out"
      rows=$i
    done
    echo "$rows $(sha256sum <"$out" | cut -d' ' -f1)" >"$out.done"
  '';
  # tribuchet-agent-swap's stop, a systemctl whose set-property fails
  # first on its PATH
  failingStop = pkgs.writeShellScript "failing-stop" ''
    mkdir -p /run/failing
    printf '#!${pkgs.runtimeShell}\n[ "$1" = set-property ] && exit 1\nexec ${pkgs.systemd}/bin/systemctl "$@"\n' >/run/failing/systemctl
    chmod +x /run/failing/systemctl
    PATH=/run/failing:$PATH ${nodes.h1.systemd.services.tribuchet-agent-swap.serviceConfig.ExecStopPost}
  '';
  node = am.node {
    memorySize = 2048;
    reserve = 768 * mib;
  };
in
{
  name = "tribuchet-agent-memory-stop";
  defaults.documentation.enable = false;
  globalTimeout = 300;
  nodes = {
    h1 = node;
    h2 = node;
  };

  extraPythonPackages = p: [ (am.checks p) ];

  testScript = ''
    import hashlib
    import os
    import re
    import time

    from checks import checker, finish, q

    SLICE = r"${slice}"
    CG = r"${cg}"
    check = checker("AGENT-MEMORY-STOP")
    start_all()
    for m in [h1, h2]:
        m.wait_for_unit("multi-user.target")
        m.wait_for_unit("tribuchet-agent-guard.service")
        m.succeed(f"systemctl start '{SLICE}'")
        m.succeed("systemd-run --unit=ssloop -p RemainAfterExit=yes ${loop} 400 140 /tmp/ss.txt")
    t0 = time.monotonic()
    while time.monotonic() < t0 + 175 and not all(m.execute("test -e /tmp/ss.txt.done")[0] == 0 for m in [h1, h2]):
        time.sleep(5)


    # The rows as the loop wrote them, given its .done line ("rows
    # sha256"): all of them, numbered 1 to rows, each whole, with an
    # InvocationID (a stop can cancel a start that has not begun: fewer
    # distinct ones), and each stop leaving 0, 0 and zswap off.
    def verdict(text: str, done: str) -> dict:
        rows = [l.split() for l in text.splitlines()]
        count, digest = (done.split() + ["", ""])[:2]
        whole = (count.isdigit() and len(rows) == int(count)
                 and hashlib.sha256(text.encode()).hexdigest() == digest
                 and [r[0] for r in rows] == [str(i) for i in range(1, len(rows) + 1)])
        stuck = [r for r in rows if len(r) != 8 or not re.fullmatch(r"[0-9a-f]{32}", r[7]) or r[2] == "active"
                 or r[4:7] != ["0", "0", "N"]]
        states: dict[str, int] = {}
        for r in rows:
            states[" ".join(r[2:4])] = states.get(" ".join(r[2:4]), 0) + 1
        return {
            "done": done,
            "whole": whole,
            "rows": len(rows),
            "ids": len({r[7] for r in rows if len(r) == 8}),
            "states": states,
            "stuck": stuck,
            "ok": done != "" and whole and len(rows) >= 100 and not stuck,
        }


    for m in [h1, h2]:
        m.copy_from_machine("/tmp/ss.txt", m.name)
        with open(os.path.join(os.environ["out"], m.name, "ss.txt"), errors="replace") as f:
            text = f.read()
        v = verdict(text, q(m, "cat /tmp/ss.txt.done"))
        check(f"{m.name}: every row the loop wrote, and a stop during the start, every time: 0 and zswap off",
              v["ok"], {k: v[k] for k in ["done", "whole", "rows", "ids", "states"]} | {"stuck": v["stuck"][:20]})
    for m in [h1, h2]:
        m.succeed("systemctl start tribuchet-agent-swap")
        rc = m.execute("${failingStop}")[0]
        cur, z = m.succeed(f"cat '{CG}/memory.swap.max' /sys/module/zswap/parameters/enabled").split()
        check(f"{m.name}: a stop whose call for 0 fails leaves zswap on", rc != 0 and cur != "0" and z == "Y",
              {"rc": rc, "memory.swap.max": cur, "zswap": z})
    finish()
  '';
}
