# The agent-memory test's runs on its 16 GiB node, one after another, as
# root outside the agents' slice; each run's process is a transient unit,
# in a cgroup of its own under the slice (as a build's) or outside it.
# Records in OUT, then OUT.done:
#   ns        1.1 times MemTotal of compressible pages outside the slice
#   tiny      A + 0.8 S of tiny pages in the slice: zswap's metadata, and
#             the RAM it holds outside the slice's charge
#   growrand  a random runaway in the slice, cut after 150 s
#   comp      1.3 A of compressible pages in the slice
# During growrand and comp, the guard's inputs once a second (trace).
# OUT is rewritten after each run.
#   slicescale.py RESERVE LAUNCH SLICEFILL OUT
import json
import os
import subprocess
import sys
import threading
import time

reserve, launch, fill, out = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
# a transient unit's PATH has no systemctl
os.environ["PATH"] = "/run/current-system/sw/bin"
SLICE = "system-tribuchet\\x2dagent.slice"
CG = f"/sys/fs/cgroup/system.slice/{SLICE}"
MIB = 1 << 20
SLABS = ["zswap_entry", "zs_handle", "zspage", "radix_tree_node"]


def rd(p):
    try:
        with open(p) as f:
            return f.read().strip()
    except OSError:
        return None


def pairs(p):
    return {
        l.split()[0]: int(l.split()[1])
        for l in (rd(p) or "").splitlines()
        if len(l.split()) == 2
    }


def num(p):
    v = rd(p)
    return int(v) if v is not None and v.isdigit() else v


def show(unit, props):
    r = subprocess.run(
        ["systemctl", "show", "-p", props, unit],
        capture_output=True,
        text=True,
        check=False,
    )
    return dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)


def slab_bytes():
    d = {}
    for s in SLABS:
        slabs, order = (
            rd(f"/sys/kernel/slab/{s}/slabs"),
            rd(f"/sys/kernel/slab/{s}/order"),
        )
        d[s] = (
            None
            if slabs is None or order is None
            else int(slabs.split()[0]) * (4096 << int(order))
        )
    return d


def zswap():
    return {
        f: num(f"/sys/kernel/debug/zswap/{f}")
        for f in ["stored_pages", "pool_total_size", "reject_compress_fail"]
    }


def zram():
    mm = rd("/sys/block/zram0/mm_stat")
    return None if mm is None else int(mm.split()[2])


def start(name, args, where, tmo, hold, readback=1):
    unit = f"scale-{name}"
    ready = f"/run/{unit}.ready"
    cmd = [
        "systemd-run",
        f"--unit={unit}",
        "-p",
        "RemainAfterExit=yes",
        "-p",
        f"RuntimeMaxSec={tmo}",
        "-p",
        "TimeoutStopSec=5",
        "-p",
        f"Environment=SLICEFILL_READY={ready}",
        "-p",
        f"Environment=SLICEFILL_HOLD={hold}",
        "-p",
        f"Environment=SLICEFILL_READBACK={readback}",
    ]
    if where == "slice":
        cmd += [f"--slice={SLICE}", launch, f"{CG}/{unit}"]
    subprocess.run(cmd + [sys.executable, fill] + args, check=True)
    return unit, ready


def active(unit):
    p = show(unit, "ActiveState,SubState")
    return p.get("ActiveState") == "activating" or (
        p.get("ActiveState") == "active" and p.get("SubState") == "running"
    )


def wait_ready(unit, ready, tmo):
    end = time.monotonic() + tmo
    while time.monotonic() < end and active(unit) and not os.path.exists(ready):
        time.sleep(0.5)
    return os.path.exists(ready)


def finish(unit, where, tmo):
    end = time.monotonic() + tmo
    while time.monotonic() < end and active(unit):
        time.sleep(0.5)
    d = {
        "unit": show(
            unit,
            "Result,ExecMainCode,ExecMainStatus,CPUUsageNSec,"
            "ExecMainStartTimestampMonotonic,ExecMainExitTimestampMonotonic",
        )
    }
    if where == "slice":
        d["cpu_usec"] = pairs(f"{CG}/{unit}/cpu.stat").get("usage_usec")
        d["events"] = pairs(f"{CG}/{unit}/memory.events")
    subprocess.run(["systemctl", "stop", unit], check=False)
    if where == "slice":
        for _ in range(50):
            try:
                os.rmdir(f"{CG}/{unit}")
                break
            except OSError:
                time.sleep(0.1)
    return d


class Trace:
    # the guard's inputs, once a second, until stopped
    def __init__(self):
        self.rows, self.stop = [], threading.Event()
        self.th = threading.Thread(target=self.run, daemon=True)
        self.th.start()

    def run(self):
        while not self.stop.is_set():
            st, ev = pairs(f"{CG}/memory.stat"), pairs(f"{CG}/memory.events.local")
            some = (rd(f"{CG}/memory.pressure") or "").split("total=", 1)
            self.rows.append(
                {
                    "t": time.monotonic(),
                    "current": num(f"{CG}/memory.current"),
                    "max": num(f"{CG}/memory.max"),
                    "swap": num(f"{CG}/memory.swap.current"),
                    "swap_max": rd(f"{CG}/memory.swap.max"),
                    "pgscan": st.get("pgscan"),
                    "pgsteal": st.get("pgsteal"),
                    "ev_max": ev.get("max"),
                    "ev_oom": ev.get("oom"),
                    "oom_kill": pairs(f"{CG}/memory.events").get("oom_kill"),
                    "some": int(some[1].split()[0]) if len(some) == 2 else None,
                }
            )
            self.stop.wait(1)

    def end(self):
        self.stop.set()
        self.th.join()
        return self.rows


def save():
    with open(out, "w") as f:
        json.dump(R, f, sort_keys=True)


R = {}
try:
    total = int(rd("/proc/meminfo").split("MemTotal:", 1)[1].split()[0]) * 1024
    R = {
        "total": total,
        "reserve": reserve,
        "slice": show(SLICE, "MemoryMax,MemorySwapMax,MemoryZSwapWriteback"),
    }
    A = int(R["slice"]["MemoryMax"])
    swap = R["slice"]["MemorySwapMax"]
    S = int(swap) if swap.isdigit() else total
    R["A"], R["S"] = A, S

    # ns: outside the slice
    z0 = zram()
    unit, ready = start(
        "ns", ["hold", "comp", str(total * 11 // 10 // MIB)], "outside", 150, 5
    )
    ok = wait_ready(unit, ready, 150)
    ucg = f"/sys/fs/cgroup/system.slice/{unit}.service"
    R["ns"] = {
        "ready": ok,
        "zram_before": z0,
        "zram": zram(),
        "zswap_max": rd(f"{ucg}/memory.zswap.max"),
        "zswap_current": num(f"{ucg}/memory.zswap.current"),
        "swap_current": num(f"{ucg}/memory.swap.current"),
        "zswpout": pairs(f"{ucg}/memory.stat").get("zswpout"),
        "zswap": zswap(),
    }
    R["ns"].update(finish(unit, "outside", 60))
    save()

    # tiny: in the slice
    b = {"slab": slab_bytes(), "zswap": zswap()}
    unit, ready = start(
        "tiny", ["hold", "tiny", str((A + S * 4 // 5) // MIB)], "slice", 150, 10, 0
    )
    ok = wait_ready(unit, ready, 150)
    r = {
        "slab": slab_bytes(),
        "zswap": zswap(),
        "slice_current": num(f"{CG}/memory.current"),
        "slice_peak": num(f"{CG}/memory.peak"),
        "slice_zswap": num(f"{CG}/memory.zswap.current"),
        "slice_swap": num(f"{CG}/memory.swap.current"),
    }
    grown = sum(max(0, (r["slab"][s] or 0) - (b["slab"][s] or 0)) for s in SLABS)
    uncharged = grown + (r["zswap"]["pool_total_size"] or 0) - (r["slice_zswap"] or 0)
    stored = (r["zswap"]["stored_pages"] or 0) - (b["zswap"]["stored_pages"] or 0)
    R["tiny"] = {
        "ready": ok,
        "before": b,
        "at_ready": r,
        "uncharged": uncharged,
        "stored": stored,
        "per_page": uncharged / stored if stored else None,
    }
    R["tiny"].update(finish(unit, "slice", 60))
    save()

    # growrand: in the slice, cut at 150 s
    tr = Trace()
    unit, ready = start("growrand", ["grow", "rand"], "slice", 150, 0)
    R["growrand"] = finish(unit, "slice", 170)
    R["trace_growrand"] = tr.end()
    save()

    # comp: in the slice
    tr = Trace()
    unit, ready = start(
        "comp", ["hold", "comp", str(A * 13 // 10 // MIB)], "slice", 150, 3
    )
    R["comp"] = {"ready": wait_ready(unit, ready, 150)}
    R["comp"].update(finish(unit, "slice", 90))
    R["trace_comp"] = tr.end()

    R["guard"] = subprocess.run(
        ["journalctl", "-u", "tribuchet-agent-guard", "-o", "cat", "--no-pager"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout[-4000:]
except (OSError, ValueError, KeyError, subprocess.SubprocessError) as e:
    # recorded: the test reports what is missing
    R["error"] = repr(e)
save()
with open(out + ".done", "w"):
    pass
