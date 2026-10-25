# A FIDEDUPERANGE between a write and its fsync(), then a crash before the
# txg syncs: ZIL replay must restore the write fsync() acknowledged.
#
# The write is logged WR_INDIRECT: with logbias=throughput, or with
# logbias=latency, no slog and a write of at least zfs_immediate_write_sz, or
# with O_DIRECT (zil_write_state()). Its data then reaches the log only
# through dmu_sync() at fsync() time. A dedupe in the same txg replaces the
# block's dirty record with a clone's, and logs nothing. OpenZFS before
# c0688a275 made dmu_sync() return EALREADY there, so fsync() logged a
# TX_WRITE2 with no block pointer and returned, and replay restored the
# pre-write content. With c0688a275, dmu_sync() returns EIO and fsync() waits
# for the txg to sync.
#
# Rows, on each of a logbias=throughput and a logbias=latency dataset:
# - a: write, dedupe, fsync. The write must survive.
# - e (latency only): O_DIRECT write, dedupe, fsync. The write must survive.
# - d: write, FICLONERANGE, fsync. The logged clone must replay.
# - b: write, fsync. A plain indirect write must replay.
# - c: write, fsync, dedupe. The write must replay.
# Rows a, e and d may each wait for a txg sync (with the fix, they do), so
# they run first; b and c run last and must be recovered by replay, which
# the test checks in the log before the crash.
{
  pkgs,
  hostConfig,
}:
let
  hostBoot = hostConfig.boot;
  length = 524288;

  prepare = pkgs.writeShellScript "zfs-fideduperange-zil-prepare" ''
    set -euxo pipefail
    # No slog. sync=standard: the hosts run sync=disabled, which logs nothing.
    zpool create -f -o ashift=12 -O checksum=off -O compression=off \
      -O atime=off -O dedup=off -O sync=standard -O mountpoint=none tank /dev/vdb
    zpool get -H -o value feature@block_cloning tank | grep -qx enabled
    head -c ${toString length} /dev/urandom > /root/X
    head -c ${toString length} /dev/urandom > /root/A
    for ds in tp lat; do
      if [ $ds = tp ]; then lb=throughput; else lb=latency; fi
      zfs create -o mountpoint=legacy -o logbias=$lb tank/$ds
      mkdir -p /t/$ds
      mount -t zfs tank/$ds /t/$ds
      # Copies use dd, never cp, which may clone.
      dd if=/root/X of=/t/$ds/S bs=128k status=none
      for f in a b c d e; do dd if=/root/A of=/t/$ds/D$f bs=128k status=none; done
      # The first commit to an empty log runs zil_create(), which waits for
      # a txg sync. Create each log now.
      head -c 4096 /dev/urandom > /t/$ds/warm
      xfs_io -c fsync /t/$ds/warm
    done
    sync
    zpool sync tank
    # Only an fsync that falls back to txg_wait_synced() may sync a txg now.
    echo 600 > /sys/module/zfs/parameters/zfs_txg_timeout
  '';

  # Runs the rows and prints each step's output and the txgs, as JSON.
  experiment = pkgs.writeText "zfs-fideduperange-zil-experiment.py" ''
    import json, subprocess
    LEN = ${toString length}
    log = []

    def run(*cmd):
        out = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
        log.append([" ".join(cmd), out.splitlines()[:1]])
        return out

    def synced():
        rows = [l.split() for l in open("/proc/spl/kstat/zfs/tank/txgs").read().splitlines()[2:]]
        return max(int(r[0]) for r in rows if len(r) > 2 and r[2] == "C")

    def direct_writes():
        for l in open("/proc/spl/kstat/zfs/tank/iostats"):
            f = l.split()
            if f and f[0] == "direct_write_count":
                return int(f[2])

    def write(p, direct=False):
        run("dd", "if=/root/X", f"of={p}", "bs=128k", "conv=notrunc", "status=none",
            *(["oflag=direct"] if direct else []))

    def dedupe(ds, p):
        run("xfs_io", "-c", f"dedupe /t/{ds}/S 0 0 {LEN}", p)

    def reflink(ds, p):
        run("xfs_io", "-c", f"reflink /t/{ds}/S 0 0 {LEN}", p)

    def fsync(p):
        run("xfs_io", "-c", "fsync", p)

    r = {"synced_0": synced(), "direct_writes_0": direct_writes()}
    for ds in ("tp", "lat"):
        write(f"/t/{ds}/Da"); dedupe(ds, f"/t/{ds}/Da"); fsync(f"/t/{ds}/Da")
    write("/t/lat/De", direct=True); dedupe("lat", "/t/lat/De"); fsync("/t/lat/De")
    for ds in ("tp", "lat"):
        write(f"/t/{ds}/Dd"); reflink(ds, f"/t/{ds}/Dd"); fsync(f"/t/{ds}/Dd")
    r["synced_1"] = synced()
    for ds in ("tp", "lat"):
        write(f"/t/{ds}/Db"); fsync(f"/t/{ds}/Db")
    for ds in ("tp", "lat"):
        write(f"/t/{ds}/Dc"); fsync(f"/t/{ds}/Dc"); dedupe(ds, f"/t/{ds}/Dc")
    r["synced_2"] = synced()
    r["direct_writes_1"] = direct_writes()
    r["log"] = log
    print(json.dumps(r))
  '';

  # The log records of one dataset from zdb, as JSON.
  zil = pkgs.writeText "zfs-fideduperange-zil-records.py" ''
    import json, re, subprocess, sys
    out = subprocess.run(["zdb", "-iiii", sys.argv[1]], capture_output=True, text=True)
    recs = []
    for l in out.stdout.splitlines():
        m = re.match(r"\s+(?:CI-)?(TX_\w+)\s+len\s+\d+, txg (\d+), seq (\d+)", l)
        if m:
            recs.append({"type": m.group(1), "txg": int(m.group(2)), "seq": int(m.group(3))})
            continue
        m = re.match(r"\s+foid (\d+), offset (?:0x)?([0-9a-f]+), length (?:0x)?([0-9a-f]+)", l)
        if m and recs:
            recs[-1].update(foid=int(m.group(1)), offset=int(m.group(2), 16),
                            length=int(m.group(3), 16))
        elif "has blkptr" in l and recs:
            recs[-1]["blkptr"] = True
    print(json.dumps({"exit": out.returncode, "records": recs}))
  '';
in
pkgs.testers.runNixOSTest {
  name = "zfs-fideduperange-zil";
  nodes.machine = {
    boot = {
      inherit (hostBoot) kernelPackages;
      supportedFilesystems = [ "zfs" ];
      zfs = {
        inherit (hostBoot.zfs) package modulePackage;
        forceImportRoot = false;
      };
    };
    networking.hostId = "deadbee3";
    virtualisation = {
      cores = 2;
      memorySize = 2048;
      emptyDiskImages = [ 2048 ];
    };
    environment.systemPackages = [
      pkgs.python3
      pkgs.xfsprogs
    ];
  };

  testScript = ''
    import json
    from typing import Any

    LEN = ${toString length}
    DS = ("tp", "lat")
    FILES = {"tp": ("S", "Da", "Db", "Dc", "Dd"), "lat": ("S", "Da", "Db", "Dc", "Dd", "De")}
    r: dict[str, Any] = {}

    # Outputs stay small: the driver's console transport truncates large ones.
    def hashes():
        h = {}
        for ds in DS:
            for l in machine.succeed(f"cd /t/{ds} && sha256sum {' '.join(FILES[ds])}").splitlines():
                v, k = l.split()
                h[f"{ds}/{k}"] = v
        return h

    def records():
        return {ds: json.loads(machine.succeed(f"python3 ${zil} tank/{ds}")) for ds in DS}

    machine.wait_for_unit("multi-user.target")
    machine.succeed("modprobe zfs")
    r["module"] = machine.succeed("cat /sys/module/zfs/version /sys/module/zfs/srcversion; "
                                  "readlink -f $(modinfo -n zfs); zfs version; uname -r").splitlines()
    machine.succeed("${prepare} >&2")
    expect = {k: v for v, k in (l.split() for l in machine.succeed("cd /root && sha256sum X A").splitlines())}
    r["experiment"] = json.loads(machine.succeed("python3 ${experiment}"))
    r["objects"] = {f"{ds}/{f}": int(machine.succeed(f"stat -c %i /t/{ds}/{f}"))
                    for ds in DS for f in FILES[ds]}
    r["pre_crash"] = hashes()
    r["synced_at_crash"] = int(machine.succeed(
        "awk 'NR>2 && $3==\"C\"{t=$1} END{print t}' /proc/spl/kstat/zfs/tank/txgs"))
    r["log_at_crash"] = records()

    machine.crash()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("modprobe zfs")
    machine.succeed("zpool list tank || zpool import -f -N -d /dev tank")
    r["health"] = machine.succeed("zpool list -H -o health tank").strip()
    r["log_at_import"] = records()
    for ds in DS:
        machine.succeed(f"mkdir -p /t/{ds} && mount -t zfs tank/{ds} /t/{ds}")
    r["post_replay"] = hashes()

    name = lambda h: {expect["X"]: "X", expect["A"]: "A"}.get(h, "other")
    r["pre_crash_names"] = {k: name(v) for k, v in r["pre_crash"].items()}
    r["post_replay_names"] = {k: name(v) for k, v in r["post_replay"].items()}
    # Each file's log records at the crash: [type, txg, has blkptr].
    r["records_by_file"] = {
        k: [[x["type"], x["txg"], x.get("blkptr", False)]
            for x in r["log_at_crash"][k.split("/")[0]]["records"] if x.get("foid") == o]
        for k, o in r["objects"].items()}
    print("RESULTS " + json.dumps(r, sort_keys=True))
    (machine.out_dir / "results.json").write_text(json.dumps(r, indent=1, sort_keys=True))

    # Every check is evaluated, and all failures are reported together.
    failed: list[str] = []

    def check(name, ok):
        if not ok:
            failed.append(name)

    ex: dict[str, Any] = r["experiment"]
    steps = [c for c, _ in ex["log"]]
    outs = {c: o for c, o in ex["log"]}
    # Preconditions: every dedupe and clone took the whole range, every
    # file held the new content before the crash, the O_DIRECT write was
    # Direct I/O, and the pool came back.
    for c in steps:
        if " dedupe " in c:
            check(f"dedupe took the range: {c}", outs[c] == [f"deduped {LEN}/{LEN} bytes at offset 0"])
        if " reflink " in c:
            check(f"clone took the range: {c}", outs[c] == [f"linked {LEN}/{LEN} bytes at offset 0"])
    check("written before the crash", all(v == "X" for v in r["pre_crash_names"].values()))
    check("O_DIRECT write was Direct I/O", ex["direct_writes_1"] > ex["direct_writes_0"])
    check("pool imported", r["health"] == "ONLINE")
    # The replay-only rows were in the log, past the last synced txg: their
    # content after the crash comes from replay, not from a txg sync.
    for ds in DS:
        for f in ("Db", "Dc"):
            recs = r["records_by_file"][f"{ds}/{f}"]
            check(f"{ds}/{f} logged indirect past the synced txg",
                  len(recs) > 0 and all(t == "TX_WRITE" and b and g > r["synced_at_crash"] for t, g, b in recs))
    # Lawful positives.
    for ds in DS:
        for f in ("Db", "Dc", "Dd"):
            check(f"{ds}/{f} replayed", r["post_replay_names"][f"{ds}/{f}"] == "X")
    # The fsync()'d write before a dedupe.
    for k in ("tp/Da", "lat/Da", "lat/De"):
        check(f"{k} keeps its fsync()'d write after the crash", r["post_replay_names"][k] == "X")

    print("FAILED " + json.dumps(failed))
    assert not failed, failed
  '';
}
