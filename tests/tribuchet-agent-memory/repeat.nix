# NixOS VM test: the agents' memory guard, each case repeated within one
# run, every repetition recorded with what shows it ran, on two nodes
# (Linux 6.18). It waits for its loops twice as long as the slowest took,
# and collects only after: in one 220 s wait the loops took
# 221-231 s and passed only as collection read them a few seconds later.
# 470 s, for the slowest node's 4 runs there (230.7 s to the last one's
# end, then 2 s).
#
# The hogchild case HOGS times on each node. In a cgroup under the slice
# that systemd does not manage, as a build's under its agent, a shell at
# OOM score 0 whose child pipeline holds 1792 MiB of random bytes, past
# A, until the guard clamps the slice's swap and the kernel OOM-kills the
# child. The shell must outlive the kill ("the filler ended with 137",
# exit 0), every kill counted in the run's cgroup by memory.events and in
# the slice. The loop that runs them is in the slice at -1000, as an
# agent. Each iteration is shown by its own cgroup, its times and the
# guard's clamp line. At each clamp systemd reloads its units, the clamp
# kept; at the second, the swap unit, before the OOM kill
# (reload-probe.nix): S must be in force after, the guard
# must say once that it stopped waiting, and end every clamp it set; it
# clamps again 33 s later, and that run takes 70-80 s. A daemon-reload
# after the guard had restored S, which reads S, does not count as one at
# a clamp.
#
# 6.18's memcg OOM killer waits for its victim. From 7.0 and 6.19.9 it no
# longer sees an exiting victim (a72f73c4dd9b): on 7.2.9, 3 of 20
# hogchild runs killed a second task (Tribuchet's DESIGN.md, Known limitations).
{ tribuchet, nixosModule }:
{ pkgs, lib, ... }:
let
  wait = 470;
  mib = 1024 * 1024;
  hogs = 4;
  slice = "system-tribuchet\\x2dagent.slice";
  cg = "/sys/fs/cgroup/system.slice/${slice}";
  bin = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.systemd
    pkgs.util-linux
  ];
  child = "${pkgs.coreutils}/bin/tr -d '\\n' </dev/urandom | ${pkgs.coreutils}/bin/head -c 1792M | ${pkgs.coreutils}/bin/tail -n 1 >/dev/null || echo \\\"the filler ended with \\$?\\\" >&2; echo ok";
  # the hogchild's shell and its child in cgroup $1, at OOM score 0
  inCgroup = ''${pkgs.bash}/bin/bash -c 'echo 0 >/proc/self/oom_score_adj; echo $$ >"$1/cgroup.procs"; exec ${pkgs.bash}/bin/bash -c "$2"' _'';
  kills = ''
    kills() {
      local k v c=0
      while read -r k v; do if [ "$k" = oom_kill ]; then c=$v; fi; done <"$1/memory.events"
      echo "$c"
    }
    # until the cgroup's tasks have exited
    drained() {
      local k v populated=1
      while [ "$populated" != 0 ]; do
        while read -r k v; do if [ "$k" = populated ]; then populated=$v; fi; done <"$1/cgroup.events"
        if [ "$populated" != 0 ]; then sleep 0.1; fi
      done
    }
  '';
  hogLoop = pkgs.writeShellScript "hog-loop" ''
    set -u
    PATH=${bin}
    n=$1 out=$2
    began=$(cut -d' ' -f1 /proc/uptime)
    cg='${cg}'
    child="${child}"
    ${kills}
    for i in $(seq 1 "$n"); do
      d=$cg/hog$i
      mkdir "$d"
      read -r swapmax <"$cg/memory.swap.max"
      s0=$(kills "$cg")
      t0=$(cut -d' ' -f1 /proc/uptime)
      timeout 150 ${inCgroup} "$d" "$child" >"/tmp/hog$i.out" 2>&1
      rc=$?
      t1=$(cut -d' ' -f1 /proc/uptime)
      drained "$d"
      k=$(kills "$d")
      s1=$(kills "$cg")
      printf '{"i": %d, "cg": "hog%d", "rc": %d, "kills": %d, "slice_kills": %d, "swap_max_before": "%s", "t0": %s, "t1": %s, "out": "%s"}\n' \
        "$i" "$i" "$rc" "$k" $((s1 - s0)) "$swapmax" "$t0" "$t1" "$(tr -c 'a-zA-Z0-9 .,:;()/_=+-' ' ' <"/tmp/hog$i.out")" >>"$out"
      rmdir "$d"
      sleep 2
    done
    echo "$began $(cut -d' ' -f1 /proc/uptime)" >"$out.done"
  '';
  probe = import ./reload-probe.nix {
    inherit
      pkgs
      bin
      cg
      slice
      ;
  };
  am = import ./node.nix {
    inherit
      tribuchet
      nixosModule
      pkgs
      lib
      ;
  };
  # as memory.nix's worker: on 3 GiB, A is about 1.25 GiB
  heldNode = {
    imports = [
      (am.node {
        memorySize = 3072;
        reserve = 1536 * mib;
      })
    ];
    systemd.services.tribuchet-agent-guard.path = [ probe.held ];
  };
  hogScript = ''
    hogn = [k618a, k618b]
    for m in hogn:
        m.wait_for_unit("multi-user.target")
        m.wait_for_unit("tribuchet-agent-guard.service")
        m.succeed(f"systemctl start '{SLICE}'")
    t0 = time.monotonic()
    for m in hogn:
        m.succeed(
            f"systemd-run --unit=hogloop --slice='{SLICE}' -p OOMScoreAdjust=-1000 -p RemainAfterExit=yes"
            f" ${hogLoop} ${toString hogs} /tmp/hogs.jsonl"
        )
        m.succeed("systemd-run --unit=reloadwatch ${probe.reloadWatch} /tmp/reloads.jsonl")
    R: dict[str, Any] = wait_done(t0, [(m, "/tmp/hogs.jsonl") for m in hogn])
    for m in hogn:
        m.succeed("touch /tmp/reloads.jsonl.stop")
    for m in hogn:
        recs = jsonl(m, "/tmp/hogs.jsonl")
        R[m.name] = {
            "kernel": q(m, "uname -r"),
            "done": m.execute("test -e /tmp/hogs.jsonl.done")[0] == 0,
            "runs": recs,
            "reloads": jsonl(m, "/tmp/reloads.jsonl"),
            "S": str(int(q(m, "awk '/^MemTotal:/ {print $2}' /proc/meminfo")) * 1024 // ${toString mib} * ${toString mib}),
            "clamps": int(q(m, "journalctl -b -u tribuchet-agent-guard -o cat | grep -c 'swap clamped at' || true")),
            "ends": int(q(m, "journalctl -b -u tribuchet-agent-guard -o cat | grep -c 'its swap is back' || true")),
            "stopped": int(q(m, "journalctl -b -u tribuchet-agent-guard -o cat | grep -c 'no longer waiting' || true")),
            "guard": q(m, "journalctl -b -u tribuchet-agent-guard -o short-monotonic --no-pager | tail -n 40"),
        }
    print("AGENT-MEMORY-REPEAT " + json.dumps(R, sort_keys=True, default=str))

    for m in hogn:
        d = R[m.name]
        dr = [r for r in d["reloads"] if r["kind"] == "daemon-reload"]
        # one after the guard had restored S reads S, and
        # tests nothing: at least one at a clamp, and those keep it
        at = [r for r in dr if r["clamp"] != d["S"]]
        check(
            f"{m.name}: a daemon-reload at a clamp leaves the clamp in force",
            len(at) >= 1 and all(r["clamp"] != "" and r["after_reload"] == r["clamp"] == r["systemd"] for r in at),
            {"kernel": d["kernel"], "S": d["S"], "at_a_clamp": len(at), "after_the_clamp": len(dr) - len(at), "reloads": dr, "clamps": d["clamps"]},
        )
        sr = [r for r in d["reloads"] if r["kind"] == "swap-reload"]
        check(
            f"{m.name}: a reload of the swap unit at a clamp, before the kill: S, the guard stops waiting, and ends every clamp",
            len(sr) == 1 and d["stopped"] == 1 and d["ends"] == d["clamps"]
            and all(r["rc"] == 0 and r["held"] == 1 and r["ended"] == 1 and r["clamp"] not in ("", d["S"])
                    and r["after_reload"] == r["systemd"] == r["then"] == d["S"] for r in sr),
            {k: d[k] for k in ["kernel", "S", "clamps", "ends", "stopped"]} | {"reloads": sr},
        )


    def hogchild(name):
        d = R[name]
        runs = d["runs"]
        outlived = [r for r in runs if r["rc"] == 0 and "the filler ended with 137" in r["out"]]
        ok = (d["done"] and len(runs) == ${toString hogs} and len(outlived) == len(runs)
              and all(r["kills"] >= 1 and r["kills"] == r["slice_kills"] for r in runs))
        return ok, {
            "kernel": d["kernel"],
            "done": d["done"],
            "spans": {k: v for k, v in R["spans"].items() if k.startswith(name + ":")},
            "runs": len(runs),
            "outlived": len(outlived),
            "per_run": [(r["i"], r["rc"], r["kills"], r["slice_kills"], round(r["t1"] - r["t0"], 1)) for r in runs],
            "clamps": d["clamps"],
        }


    for m in hogn:
        ok, detail = hogchild(m.name)
        check(f"{m.name}: hogchild ${toString hogs} times: the shell outlives its child's OOM kill", ok, detail)
  '';
in
{
  name = "tribuchet-agent-memory-repeat";
  defaults.documentation.enable = false;
  # boot, WAIT and the collection: about 40 s besides the loops
  globalTimeout = 600;

  nodes = {
    k618a = heldNode;
    k618b = heldNode;
  };

  extraPythonPackages = p: [ (am.checks p) ];

  testScript = ''
    import json
    import time
    from typing import Any

    from checks import checker, finish, q

    SLICE = r"${slice}"
    WAIT = ${toString wait}
    UNPARSED: dict[str, list[str]] = {}
    check = checker("AGENT-MEMORY-REPEAT")

    # rows that parse; the others, as in a run's last line cut short, kept
    # aside in UNPARSED, so that a count that needs them fails
    def jsonl(m, f):
        rows, bad = [], []
        for l in q(m, f"cat {f}").split("\n"):
            try:
                rows.append(json.loads(l))
            except ValueError:
                bad += [l] if l.strip() else []
        UNPARSED[f"{m.name}:{f}"] = bad
        return rows


    # Until every loop is done, WAIT s from t0 at most; then each loop's
    # span, from the uptimes at its start and end in its .done, and the
    # time waited: the margin is WAIT - elapsed.
    def wait_done(t0, done):
        while time.monotonic() < t0 + WAIT and not all(m.execute(f"test -e {f}.done")[0] == 0 for m, f in done):
            time.sleep(5)
        spans = {}
        for m, f in done:
            r = q(m, f"cat {f}.done 2>/dev/null || true").split()
            spans[f"{m.name}:{f}"] = round(float(r[1]) - float(r[0]), 1) if len(r) == 2 else None
        return {"elapsed": time.monotonic() - t0, "wait": WAIT, "spans": spans}


    start_all()
  ''
  + hogScript
  + ''
    print("AGENT-MEMORY-REPEAT-UNPARSED " + json.dumps(UNPARSED))
    finish()
  '';
}
