# Test script of the agent-memory VM test (memory.nix appends
# the call of main, with the driver's machines and functions). Measures
# first, prints it all (AGENT-MEMORY), then reports each check
# (AGENT-MEMORY-CHECK) and fails on any that failed.
import json
import re
import time
from typing import Any

from checks import CHECKS, checker, finish, q

SLICE = "system-tribuchet\\x2dagent.slice"
CG = "/sys/fs/cgroup/system.slice/" + SLICE
MIB = 1 << 20
PER_PAGE = 256
check = checker("AGENT-MEMORY")


def vm_text(m: Any, path: str) -> str:
    m.copy_from_machine(path)
    return (m.out_dir / path.rsplit("/", 1)[1]).read_text(errors="replace")


def sizes(m: Any, reserve: int) -> dict[str, int]:
    # the module's arithmetic: S is MemTotal in whole MiB, A leaves the
    # reserve and 256 bytes per page of S
    total = int(q(m, "awk '/^MemTotal:/ {print $2}' /proc/meminfo")) * 1024
    s = total // MIB * MIB
    return {
        "total": total,
        "S": s,
        "A": total - reserve - s // 4096 * PER_PAGE,
        "floor": reserve * 409600 // (409600 - 100 * PER_PAGE) + 1,
    }


def state(m: Any) -> dict[str, str]:
    files = {
        "cg_memory_max": "memory.max",
        "cg_swap_max": "memory.swap.max",
        "cg_writeback": "memory.zswap.writeback",
    }
    d = {k: q(m, f"cat '{CG}/{f}' 2>&1") for k, f in files.items()}
    for k in ["MemoryMax", "MemorySwapMax", "MemoryZSwapWriteback"]:
        d["unit_" + k] = q(m, f"systemctl show -P {k} '{SLICE}'")
    for k in ["enabled", "compressor", "max_pool_percent"]:
        d["zswap_" + k] = q(m, f"cat /sys/module/zswap/parameters/{k}")
    for u in ["tribuchet-agent-swap", "tribuchet-agent-guard"]:
        d[u] = q(m, f"systemctl show -P ActiveState {u}.service")
    return d


def slice_ok(st: dict[str, str], W: dict[str, int], R: dict[str, Any]) -> bool:
    # A, S, writeback off; zswap on (zstd, pool 100 %); the units; AssertMemory
    return (
        st["cg_memory_max"] == str(W["A"])
        and st["unit_MemoryMax"] == str(W["A"])
        and st["cg_swap_max"] == str(W["S"])
        and st["unit_MemorySwapMax"] == str(W["S"])
        and st["cg_writeback"] == "0"
        and st["unit_MemoryZSwapWriteback"] == "no"
        and (st["zswap_enabled"], st["zswap_compressor"], st["zswap_max_pool_percent"])
        == ("Y", "zstd", "100")
        and st["tribuchet-agent-swap"] == "active"
        and st["tribuchet-agent-guard"] == "active"
        and R["assert_memory"] == f"AssertMemory=>{W['floor']}"
        and R["zram_disksize"] > 0
        and R["init_zswap_max"] == "0"
    )


def mon_rows(m: Any) -> list[Any]:
    m.succeed("systemctl stop slicemon")
    return [
        json.loads(line)
        for line in vm_text(m, "/tmp/slicemon.jsonl").splitlines()
        if line.strip()
    ]


def peak(rows: list[Any], key: str) -> int:
    return max(
        (int(r[key]) for r in rows if r.get(key) not in (None, "max")), default=-1
    )


def main(
    hub: Any,
    worker: Any,
    big: Any,
    start_all: Any,
    subtest: Any,
    monitor: str,
    launch: str,
    scale: str,
    fill: str,
    reserve: int,
) -> None:
    R: dict[str, Any] = {"reserve": reserve}
    t0 = time.monotonic()
    start_all()
    for m in [hub, worker, big]:
        m.wait_for_unit("multi-user.target")
    # the 16 GiB node runs its own sequence meanwhile (slicescale.py)
    big.succeed(
        f"systemd-run --unit=slicemon python3 {monitor} '{CG}' /tmp/slicemon.jsonl 0.25"
    )
    big.succeed(
        f"systemd-run --unit=scale python3 {scale} {reserve} {launch} {fill} /tmp/scale.json"
    )

    with subtest("certificates and registration"):
        hub.succeed("tribuchet ca init --dir /root/ca")
        hub.succeed("tribuchet ca issue hub --dir /root/ca")
        hub.succeed("tribuchet ca issue worker --dir /root/ca")
        hub.succeed("mkdir -p /etc/tribuchet/ca")
        hub.succeed(
            "cp /root/ca/hub.crt /root/ca/hub.key /root/ca/ca.crt /etc/tribuchet/ca/"
        )
        worker.succeed("mkdir -p /etc/tribuchet/tls")
        for f in ["worker.crt", "worker.key", "ca.crt"]:
            pem = hub.succeed(f"cat /root/ca/{f}")
            worker.succeed(f"cat > /etc/tribuchet/tls/{f} << 'PEMEOF'\n{pem}PEMEOF")
        worker.succeed("chmod 600 /etc/tribuchet/tls/worker.key")
        hub.succeed("systemctl start tribuchet-hub.socket tribuchet-hub")
        worker.succeed("systemctl start tribuchet-worker")
        hub.wait_until_succeeds(
            "journalctl -u tribuchet-hub | grep -q 'worker registered'"
        )

    R["kernel"] = q(worker, "uname -r")
    R["worker_sizes"] = W = sizes(worker, reserve)
    R["assert_memory"] = q(
        worker, "systemctl cat tribuchet-worker | grep '^AssertMemory=' || true"
    )
    R["zram_disksize"] = int(q(worker, "cat /sys/block/zram0/disksize"))
    R["init_zswap_max"] = q(worker, "cat /sys/fs/cgroup/init.scope/memory.zswap.max")
    # Judged before the builds, which a slice set up wrong (say, swapping
    # with zswap off) can hang past the test's timeout.
    R["state_boot"] = state(worker)
    check(
        "before the builds, the slice: A, S, writeback off; zswap on (zstd, pool 100 %); the units; AssertMemory",
        slice_ok(R["state_boot"], W, R),
        [R["state_boot"], W, R["assert_memory"], R["init_zswap_max"]],
    )
    if not all(CHECKS.values()):
        print("AGENT-MEMORY " + json.dumps(R, sort_keys=True, default=str))
        finish()
    worker_pid = q(worker, "systemctl show -P MainPID tribuchet-worker")
    hub_pid = q(hub, "systemctl show -P MainPID tribuchet-hub")
    worker.succeed("echo builds > /run/phase")
    worker.succeed(
        f"systemd-run --unit=slicemon python3 {monitor} '{CG}' /tmp/slicemon.jsonl 0.1"
    )

    def build(name: str, limit: int) -> dict[str, Any]:
        rc, out = hub.execute(
            f"timeout {limit} nix-build /etc/tt/slice-{name}.nix --no-out-link 2>&1",
            timeout=limit + 60,
        )
        return {"rc": rc, "tail": out[-3000:]}

    with subtest(
        "builds past the cap, runaways, a child killed, a build's memory no task counts"
    ):
        for name, limit in [
            ("comp", 300),
            ("growzero", 150),
            ("growrand", 150),
            ("hogchild", 180),
            ("shm", 150),
            ("small", 60),
        ]:
            R[name] = build(name, limit)
        R["state"] = state(worker)

    rows = mon_rows(worker)
    live = [r for r in rows if r["memory.current"] is not None]
    on = [r for r in live if r["phase"] == "builds"]
    R["mon_rows"], R["mon_on"] = len(rows), len(on)
    R["max_slice_plus_zram"] = max(
        (int(r["memory.current"]) + (r["zram_mem_used"] or 0) for r in on), default=-1
    )
    R["max_swap"] = peak(on, "memory.swap.current")
    R["max_zswap"] = peak(on, "memory.zswap.current")
    R["events_local"] = live[-1]["events"] if live else {}
    # OOM kills are counted by the kernel's counters (/proc/vmstat
    # oom_kill, the slice's memory.events oom_kill), never by lines in
    # journald's copy of the kernel log, which can miss some (24 of 59
    # kills in one run). That copy only says whose cgroup a victim was
    # in: a lost line can hide an agent's kill, not invent one, and that
    # agents are exempt is checked where it is set (-1000, below).
    worker.succeed("journalctl --sync")
    worker.succeed("journalctl -k -a --no-pager > /tmp/kernel.txt")
    kernel = vm_text(worker, "/tmp/kernel.txt")
    R["oom_kills"] = re.findall(r"oom-kill:\S+", kernel)
    R["kills"] = {
        "vmstat": int(q(worker, "awk '$1 == \"oom_kill\" {print $2}' /proc/vmstat")),
        "slice": int(
            q(worker, f"awk '$1 == \"oom_kill\" {{print $2}}' '{CG}/memory.events'")
        ),
    }
    R["guard_log"] = q(
        worker, "journalctl -u tribuchet-agent-guard -o cat --no-pager | tail -n 20"
    )
    hub.succeed("journalctl -a -u tribuchet-hub --no-pager > /tmp/hub.txt")
    usage = [
        re.sub(r"\x1b\[[0-9;]*m", "", line)
        for line in vm_text(hub, "/tmp/hub.txt").splitlines()
        if "build usage" in line
    ]
    names = ["comp", "growzero", "growrand", "hogchild", "shm", "small"]
    R["usage"] = {
        n: [u.split("build usage ", 1)[1] for u in usage if f'drv="tt-slice-{n}"' in u]
        for n in names
    }
    R["worker_pid_same"] = (
        q(worker, "systemctl show -P MainPID tribuchet-worker") == worker_pid
    )
    R["hub_pid_same"] = q(hub, "systemctl show -P MainPID tribuchet-hub") == hub_pid

    # up to 520 s into the test (of 570), then whatever the runs recorded
    while (
        time.monotonic() < t0 + 520
        and big.execute("test -e /tmp/scale.json.done")[0] != 0
    ):
        time.sleep(2)
    R["big_done"] = big.execute("test -e /tmp/scale.json.done")[0] == 0
    B: dict[str, Any] = (
        json.loads(vm_text(big, "/tmp/scale.json"))
        if big.execute("test -e /tmp/scale.json")[0] == 0
        else {}
    )
    R["big"] = B
    R["big_sizes"] = BS = sizes(big, reserve)
    brows = [r for r in mon_rows(big) if r["memory.current"] is not None]
    R["big_max_current"] = peak(brows, "memory.current")
    print("AGENT-MEMORY " + json.dumps(R, sort_keys=True, default=str))

    def usage_field(name: str, field: str) -> list[int]:
        return [
            int(v) for u in R["usage"][name] for v in re.findall(rf"\b{field}=(\d+)", u)
        ]

    agents = [k for k in R["oom_kills"] if re.search(r"task_memcg=[^,]*/agent,", k)]
    S, A = W["S"], W["A"]

    check(
        "comp, 1.35 A of pages that compress, succeeds",
        R["comp"]["rc"] == 0 and any("exit_code=0" in u for u in R["usage"]["comp"]),
        [R["comp"], R["usage"]["comp"]],
    )
    for n in ["growzero", "growrand"]:
        check(
            f"{n} is OOM-killed in the slice and fails, within 90 CPU-s",
            R[n]["rc"] not in (0, 124)
            and any("oom_killed=true" in u for u in R["usage"][n])
            and all(c < 90_000_000 for c in usage_field(n, "cpu_usec")),
            [R[n], R["usage"][n]],
        )
    check(
        "hogchild outlives its child's OOM kill and succeeds",
        R["hogchild"]["rc"] == 0
        and "the filler ended with 137" in R["hogchild"]["tail"]
        and any(
            "exit_code=0" in u and "oom_killed=true" in u
            for u in R["usage"]["hogchild"]
        ),
        [R["kernel"], R["hogchild"], R["usage"]["hogchild"]],
    )
    K = R["kills"]
    # The counts agree for a global OOM kill of a task in the slice too:
    # each kill the kernel log kept must also be the slice's own OOM
    # killer's (a lost line hides a kill, it cannot invent one).
    outside = [
        k
        for k in R["oom_kills"]
        if not k.startswith("oom-kill:constraint=CONSTRAINT_MEMCG,")
        or f",oom_memcg=/system.slice/{SLICE}," not in k
    ]
    check(
        "every OOM kill is the slice's",
        K["vmstat"] == K["slice"] >= 3 and R["oom_kills"] and not outside,
        [K, len(R["oom_kills"]), outside[:5]],
    )
    check(
        "no agent is OOM-killed, not even past S with memory no task counts (shm);"
        " the worker and the hub stay up",
        not agents
        and R["small"]["rc"] == 0
        and R["worker_pid_same"]
        and R["hub_pid_same"],
        [agents, R["shm"], R["small"]],
    )
    check(
        "the slice and zram hold at most A; the slice swaps through zswap, at most S",
        on
        and R["max_slice_plus_zram"] <= A + MIB
        and R["max_zswap"] > 0
        and R["max_swap"] <= S,
        [R["max_slice_plus_zram"], A, R["max_zswap"], R["max_swap"], S],
    )
    check(
        "after the builds, the slice: A, S, writeback off; zswap on (zstd, pool 100 %); the units; AssertMemory",
        slice_ok(R["state"], W, R),
        [R["state"], W],
    )
    ns, tiny, rand, comp = (
        B.get("ns", {}),
        B.get("tiny", {}),
        B.get("growrand", {}),
        B.get("comp", {}),
    )
    check(
        "at 16 GiB, a process outside the slice swaps to zram, never into zswap",
        ns.get("ready")
        and ns.get("zswap_max") == "0"
        and ns.get("zswpout") == 0
        and ns.get("zswap_current") == 0
        and (ns.get("zram") or 0) - (ns.get("zram_before") or 0) > 64 * MIB,
        [ns, B.get("error")],
    )
    bound = BS["total"] - reserve
    check(
        "at 16 GiB, the slice's RAM and zswap's uncharged metadata stay within MemTotal less the reserve",
        tiny.get("ready")
        and tiny.get("events", {}).get("oom_kill") == 0
        and R["big_max_current"] + tiny.get("uncharged", bound) <= bound
        and (tiny.get("per_page") or PER_PAGE + 1) <= PER_PAGE,
        [
            R["big_max_current"],
            tiny.get("uncharged"),
            bound,
            tiny.get("per_page"),
            tiny.get("stored"),
        ],
    )
    check(
        "at 16 GiB, a random runaway is OOM-killed in the slice before 150 s",
        rand.get("events", {}).get("oom_kill", 0) >= 1
        and rand.get("unit", {}).get("Result") != "timeout",
        [rand, B.get("guard"), R["big_done"]],
    )
    check(
        "at 16 GiB, a build of 1.3 A that compresses succeeds",
        comp.get("ready")
        and comp.get("events", {}).get("oom_kill") == 0
        and comp.get("unit", {}).get("ExecMainStatus") == "0",
        comp,
    )
    finish()
