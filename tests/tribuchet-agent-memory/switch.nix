# NixOS VM test: taking the agents' memory settings off a running host
# with switch-to-configuration must leave the slice as on a host booted
# without them. sw boots with agentMemoryReserve set (agentSwapPercent at
# its default) and switches to agentSwapPercent = 0, back, and then to
# agentMemoryReserve = null, whose option text promises "no cap, no swap
# limit, zswap left as the host boots it"; ref boots with it null. After the last switch
# the slice's MemoryMax, MemorySwapMax, memory.max, memory.swap.max and
# zswap must be ref's, and a build in the slice that needs swap (1.3 times
# MemTotal of pages that compress about 4 to 1) must succeed on sw as it
# does on ref. Everything is measured and printed (AGENT-MEMORY-SWITCH)
# before it is checked, and each check is reported on its own
# (AGENT-MEMORY-SWITCH-CHECK) before the test fails.
#
# A tribuchet-agent-swap whose stop writes MemorySwapMax=0 with
# `systemctl set-property --runtime` fails it: nothing removes that
# drop-in (/run/systemd/system.control/<slice>.d/50-MemorySwapMax.conf)
# before the next boot.
{ tribuchet, nixosModule }:
{ pkgs, lib, ... }:
let
  mib = 1024 * 1024;
  reserve = 768 * mib;
  am = import ./node.nix {
    inherit
      tribuchet
      nixosModule
      pkgs
      lib
      ;
  };
  node = am.node {
    memorySize = 3072;
    inherit reserve;
  };
in
{
  name = "tribuchet-agent-memory-switch";
  defaults.documentation.enable = false;
  globalTimeout = 660;

  nodes = {
    sw =
      { ... }:
      {
        imports = [ node ];
        system.switch.enable = true;
        specialisation = {
          off.configuration.services.tribuchet-worker.agentSwapPercent = lib.mkForce 0;
          nul.configuration.services.tribuchet-worker.agentMemoryReserve = lib.mkForce null;
        };
      };
    ref =
      { ... }:
      {
        imports = [ node ];
        services.tribuchet-worker.agentMemoryReserve = lib.mkForce null;
      };
  };

  extraPythonPackages = p: [ (am.checks p) ];

  testScript = ''
    import json
    import time
    from typing import Any

    from checks import checker, finish, q

    SLICE = "system-tribuchet\\x2dagent.slice"
    CG = "/sys/fs/cgroup/system.slice/" + SLICE
    check = checker("AGENT-MEMORY-SWITCH")


    def state(m):
        return {
            "MemoryMax": q(m, f"systemctl show -P MemoryMax '{SLICE}'"),
            "MemorySwapMax": q(m, f"systemctl show -P MemorySwapMax '{SLICE}'"),
            "memory.max": q(m, f"cat '{CG}/memory.max'"),
            "memory.swap.max": q(m, f"cat '{CG}/memory.swap.max'"),
            "zswap": q(m, "cat /sys/module/zswap/parameters/enabled"),
            "zswap_max_pool_percent": q(m, "cat /sys/module/zswap/parameters/max_pool_percent"),
            "journald_zswap_max": q(m, "cat /sys/fs/cgroup/system.slice/systemd-journald.service/memory.zswap.max"),
            "units": q(m, "systemctl is-active tribuchet-agent-swap tribuchet-agent-guard || true"),
            "dropins": q(m, f"systemctl show -P DropInPaths '{SLICE}'"),
        }


    def switch(to):
        path = "/run/booted-system/bin" if to == "base" else f"/run/booted-system/specialisation/{to}/bin"
        rc, out = sw.execute(f"{path}/switch-to-configuration test 2>&1")
        return {"rc": rc, "out": out[-2000:]}


    def need_swap(m):
        kib = int(q(m, "awk '/^MemTotal:/ {print $2}' /proc/meminfo"))
        n = kib * 13 // 10 // 1024
        m.succeed(
            f"systemd-run --unit=need-swap --slice='{SLICE}' -p RemainAfterExit=yes -p RuntimeMaxSec=200 "
            "-p Environment=SLICEFILL_READY=/run/need-swap.ready -p Environment=SLICEFILL_HOLD=0 "
            f"${pkgs.python3}/bin/python3 -I ${./slicefill.py} hold comp {n}"
        )
        return n


    def need_swap_result(m):
        return {
            k: q(m, f"systemctl show -P {k} need-swap")
            for k in ["ActiveState", "SubState", "Result", "ExecMainStatus", "MemoryPeak", "MemorySwapPeak"]
        } | {
            "global_oom": q(m, "dmesg | grep -c global_oom || true"),
            "slice_oom_kill": q(m, f"grep oom_kill '{CG}/memory.events' || true"),
        }


    def done(m):
        a = q(m, "systemctl show -P ActiveState need-swap")
        s = q(m, "systemctl show -P SubState need-swap")
        return a in ("failed", "inactive") or (a == "active" and s == "exited")


    start_all()
    for m in (sw, ref):
        m.wait_for_unit("multi-user.target")
        # the slice's cgroup, so its files can be read on both nodes
        m.execute(f"systemctl start '{SLICE}'")
    R: dict[str, Any] = {"ref": state(ref), "boot": state(sw)}
    for to, label in [("off", "off"), ("base", "base"), ("nul", "nul")]:
        R[label + "_switch"] = switch(to)
        R[label] = state(sw)
    R["need_swap_mib"] = {m.name: need_swap(m) for m in (sw, ref)}
    deadline = time.monotonic() + 230
    while time.monotonic() < deadline and not (done(sw) and done(ref)):
        time.sleep(2)
    R["need_swap"] = {m.name: need_swap_result(m) for m in (sw, ref)}
    print("AGENT-MEMORY-SWITCH " + json.dumps(R, sort_keys=True))

    keys = ["MemoryMax", "MemorySwapMax", "memory.max", "memory.swap.max", "zswap"]
    o, b, n, r = R["off"], R["base"], R["nul"], R["ref"]
    check(
        "switched to agentSwapPercent = 0: the slice may not swap, zswap off and for no unit",
        R["off_switch"]["rc"] == 0 and o["MemorySwapMax"] == "0" and o["memory.swap.max"] == "0"
        and o["zswap"] == "N" and o["journald_zswap_max"] == "max" and o["units"].split() == ["inactive", "inactive"],
        {"off": o},
    )
    check(
        "switched back: S and zswap for the slice alone as at boot",
        R["base_switch"]["rc"] == 0 and all(b[k] == R["boot"][k] for k in keys + ["journald_zswap_max"]),
        {"boot": R["boot"], "base": b},
    )
    check(
        "switched to agentMemoryReserve = null: the slice as on a host booted with it null (no cap, no swap limit)",
        R["nul_switch"]["rc"] == 0 and all(n[k] == r[k] for k in keys),
        {"nul": {k: n[k] for k in keys}, "ref": {k: r[k] for k in keys}, "dropins": n["dropins"]},
    )
    check(
        "ref: a slice build that needs swap succeeds",
        R["need_swap"]["ref"]["Result"] == "success" and R["need_swap"]["ref"]["ExecMainStatus"] == "0",
        R["need_swap"]["ref"],
    )
    check(
        "switched to agentMemoryReserve = null: a slice build that needs swap succeeds, as on ref",
        R["need_swap"]["sw"]["Result"] == "success" and R["need_swap"]["sw"]["ExecMainStatus"] == "0",
        R["need_swap"]["sw"],
    )
    finish()
  '';
}
