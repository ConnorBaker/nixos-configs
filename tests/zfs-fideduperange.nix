# zfs-dedup against the hosts' ZFS, in a VM.
#
# patched = true runs the hosts' patched userspace and module (the FIDEDUPERANGE
# backport); patched = false runs the stock zfs_unstable pair from the same
# nixpkgs, as the negative control. Both run the same scenario:
#
# - A pool with the hosts' dataset properties and block_cloning, a dataset
#   laid out like /nix with a read-only bind mount of its store, and a home
#   dataset. Duplicate files have known mtimes: 1 under the store, other
#   fixed values (and setuid/setgid bits) under home.
# - FIDEDUPERANGE called directly: identical ranges, then differing ones.
# - zfs-dedup without --force, then (stock only) with --force.
# - A pair that changes between zfs-dedup's hash and its clone. strace delays
#   the pair's dedupe/clone ioctl, and the destination is rewritten during
#   the delay.
{
  pkgs,
  hostConfig,
  patched,
}:
let
  hostBoot = hostConfig.boot;
  zfsPackage = if patched then hostBoot.zfs.package else pkgs.zfs_unstable;
  zfsModulePackage =
    if patched then
      hostBoot.zfs.modulePackage
    else
      hostBoot.kernelPackages.${pkgs.zfs_unstable.kernelModuleAttribute};

  # Lays out the pool. Copies use dd, never cp or cat, which may clone.
  setup = pkgs.writeShellScript "zfs-fideduperange-setup" ''
    set -euxo pipefail
    # rootFsOptions and pool options from util.nix's zfsStripedPoolCommonConfig.
    zpool create -f -o ashift=12 -o autotrim=on \
      -O acltype=posixacl -O atime=off -O canmount=off -O checksum=off \
      -O compression=off -O dedup=off -O dnodesize=auto -O normalization=formD \
      -O redundant_metadata=none -O sync=disabled -O xattr=sa \
      -O mountpoint=none tank /dev/vdb
    zpool get -H -o value feature@block_cloning tank | grep -qx enabled
    for ds in nix home; do zfs create -o canmount=on -o mountpoint=legacy tank/$ds; done
    mkdir -p /tnix /thome
    mount -t zfs tank/nix /tnix
    mount -t zfs tank/home /thome

    rnd() { mkdir -p "$(dirname "$1")"; head -c "$2" /dev/urandom > "$1"; }
    dup() { mkdir -p "$(dirname "$2")"; dd if="$1" of="$2" bs=1M status=none; }

    S=/tnix/store
    rnd $S/aaaa-pkg-1/lib/libfoo.so 1048576
    dup $S/aaaa-pkg-1/lib/libfoo.so $S/bbbb-pkg-2/lib/libfoo.so
    rnd $S/aaaa-pkg-1/share/data.bin 300000
    dup $S/aaaa-pkg-1/share/data.bin $S/bbbb-pkg-2/share/data.bin
    rnd $S/cccc-pkg-3/bin/tool 2097152
    dup $S/cccc-pkg-3/bin/tool $S/dddd-pkg-4/bin/tool
    dup $S/cccc-pkg-3/bin/tool $S/eeee-pkg-5/bin/tool
    rnd $S/aaaa-pkg-1/share/small 1000
    dup $S/aaaa-pkg-1/share/small $S/bbbb-pkg-2/share/small
    rnd $S/aaaa-pkg-1/share/unique 262144
    find $S -mindepth 1 -type f -exec chmod 0444 {} +
    chmod 0555 $S/*/bin/tool
    find $S -mindepth 1 -type d -exec chmod 0555 {} +
    # Canonical store timestamps: everything at mtime 1, files before dirs.
    find $S -mindepth 1 -depth -exec touch -h -d @1 {} +

    H=/thome/u
    rnd $H/x.bin 2097152
    dup $H/x.bin $H/y.bin
    touch -d '2020-01-02 03:04:05.123456789 UTC' $H/x.bin
    touch -d '2021-06-07 08:09:10.987654321 UTC' $H/y.bin
    rnd $H/suid-a 262144
    dup $H/suid-a $H/suid-b
    chmod 6755 $H/suid-a $H/suid-b
    touch -d '2019-01-01 00:00:00 UTC' $H/suid-a $H/suid-b

    # NixOS mounts the store as a read-only bind of itself.
    mount --bind $S $S
    mount -o remount,bind,ro,nosuid,nodev $S
    findmnt -no SOURCE,FSTYPE,OPTIONS $S
    sync
    zpool sync tank
  '';

  # Every path under the roots: stat fields, plus sha256 for regular files.
  snapshot = pkgs.writeText "snapshot.py" ''
    import hashlib, json, os, stat, sys
    out = {}
    for root in sys.argv[2:]:
        for dp, dns, fns in os.walk(root):
            for p in [dp] + [os.path.join(dp, f) for f in fns]:
                st = os.lstat(p)
                e = {k: getattr(st, "st_" + k) for k in
                     ("mode", "uid", "gid", "size", "ino", "nlink",
                      "mtime_ns", "ctime_ns")}
                if stat.S_ISREG(st.st_mode):
                    h = hashlib.sha256()
                    with open(p, "rb") as f:
                        for b in iter(lambda: f.read(1 << 20), b""):
                            h.update(b)
                    e["sha256"] = h.hexdigest()
                out[p] = e
    with open(sys.argv[1], "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
  '';

  # One FIDEDUPERANGE call: src len dst. Prints the ioctl result as JSON.
  fdr = pkgs.writeText "fdr.py" ''
    import fcntl, json, os, struct, sys
    FIDEDUPERANGE = 0xC0189436  # _IOWR(0x94, 54, struct file_dedupe_range)
    src, length, dst = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    s = os.open(src, os.O_RDONLY)
    d = os.open(dst, os.O_RDWR)
    arg = struct.pack("QQHHI", 0, length, 1, 0, 0) + struct.pack("qQQiI", d, 0, 0, 0, 0)
    try:
        r = fcntl.ioctl(s, FIDEDUPERANGE, arg)
        _, _, deduped, status, _ = struct.unpack("qQQiI", r[24:])
        print(json.dumps({"errno": 0, "status": status, "bytes_deduped": deduped}))
    except OSError as e:
        print(json.dumps({"errno": e.errno, "status": None, "bytes_deduped": None}))
  '';

  # zfs-dedup on one directory holding a pair that is identical when hashed.
  # strace delays the pair's FIDEDUPERANGE/FICLONERANGE at entry; during the
  # delay the destination's first 128 KiB is rewritten.
  race = pkgs.writeText "race.py" ''
    import hashlib, json, os, re, subprocess, sys, time
    d, force = sys.argv[1], sys.argv[2] == "force"
    log = "/root/race.log"
    def sha(p):
        with open(p, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    before = {n: sha(f"{d}/{n}") for n in ("a", "b")}
    cmd = ["strace", "-f", "-qq", "-P", f"{d}/a", "-P", f"{d}/b",
           "-e", "trace=openat,ioctl", "-e", "inject=ioctl:delay_enter=20000000",
           "zfs-dedup", "-c", "/root/race.redb"] + (["-f"] if force else []) + [d]
    with open(log, "w") as lf:
        p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=lf)
    res = {"cmd": cmd, "before": before, "triggered": None}
    deadline = time.time() + 120
    while time.time() < deadline and p.poll() is None:
        txt = open(log).read()
        # FIDEDUPERANGE is issued on the source; the destination is dest_fd.
        # FICLONERANGE is issued on the destination. Wait for the whole field.
        m = (re.search(r"ioctl\(\d+, [^,\n]*?(FIDEDUPERANGE), \{[^\n]*?dest_fd=(\d+),", txt)
             or re.search(r"ioctl\((\d+), [^,\n]*?(FICLONERANGE), \{src_fd=\d+,", txt))
        if m:
            kind = "FIDEDUPERANGE" if "FIDEDUPERANGE" in m.group(0) else "FICLONERANGE"
            fd = m.group(2) if kind == "FIDEDUPERANGE" else m.group(1)
            # The traced zfs-dedup is strace's child.
            pid = subprocess.run(["pgrep", "-P", str(p.pid)], capture_output=True,
                                 text=True).stdout.split()[0]
            dst = os.readlink(f"/proc/{pid}/fd/{fd}")
            new = os.urandom(131072)
            w = os.open(dst, os.O_WRONLY)
            os.pwrite(w, new, 0)
            os.close(w)
            res.update(triggered=kind, dst=dst, written=sha(dst),
                       written_at=time.time())
            break
        time.sleep(0.05)
    rc = p.wait(timeout=180)
    res["exit"] = rc
    res["after"] = {n: sha(f"{d}/{n}") for n in ("a", "b")}
    res["summary"] = [l for l in open(log).read().splitlines() if "mismatches" in l]
    print(json.dumps(res))
  '';

  # Compares two snapshots in the VM and prints a compact summary: the test
  # driver's console transport truncates large outputs.
  snapdiff = pkgs.writeText "snapdiff.py" ''
    import json, stat, sys
    a, b = (json.load(open(f)) for f in sys.argv[1:3])
    changed = {}
    for p in sorted(set(a) | set(b)):
        x, y = a.get(p) or {}, b.get(p) or {}
        if x != y:
            changed[p] = {k: [x.get(k), y.get(k)] for k in sorted(set(x) | set(y)) if x.get(k) != y.get(k)}
    fields = sorted({k for d in changed.values() for k in d})
    reg = lambda p: p in a and stat.S_ISREG(a[p]["mode"])
    print(json.dumps({
        "n": len(changed), "fields": fields,
        "regular_files": sum(1 for p in a if reg(p)),
        "regular_changed": sorted(p for p in changed if reg(p)),
        "store_mtime_changed": sum(1 for p, d in changed.items() if p.startswith("/tnix/store/") and "mtime_ns" in d),
        "store_mtime_not_1": sum(1 for p, e in b.items() if p.startswith("/tnix/store/") and e["mtime_ns"] != 1_000_000_000),
        "sample": dict(list(changed.items())[:6]),
    }))
  '';

  # L0 block pointers of two files from zdb; prints how many are shared.
  sharing = pkgs.writeText "sharing.py" ''
    import json, re, subprocess, sys
    ds, a, b = sys.argv[1:4]
    def l0(rel):
        p = subprocess.run(["zdb", "-vvvvv", ds, "-O", rel], capture_output=True, text=True)
        if p.returncode != 0:
            raise RuntimeError(f"zdb {ds} {rel}: rc={p.returncode}: {(p.stdout + p.stderr)[-300:]}")
        return [m.group(0) for l in p.stdout.splitlines()
                if " L0 " in l and (m := re.search(r"\d+:[0-9a-f]+:[0-9a-f]+", l))]
    try:
        x, y = l0(a), l0(b)
        print(json.dumps({"blocks": [len(x), len(y)], "shared": sum(1 for i, j in zip(x, y) if i == j)}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
  '';
in
pkgs.testers.runNixOSTest {
  name = "zfs-fideduperange-${if patched then "patched" else "stock"}";
  nodes.machine = {
    boot = {
      inherit (hostBoot) kernelPackages;
      supportedFilesystems = [ "zfs" ];
      zfs = {
        package = zfsPackage;
        modulePackage = zfsModulePackage;
        forceImportRoot = false;
      };
    };
    networking.hostId = "deadbee1";
    virtualisation = {
      cores = 2;
      memorySize = 2048;
      emptyDiskImages = [ 2048 ];
    };
    environment.systemPackages = [
      pkgs.python3
      pkgs.strace
      pkgs.zfs-dedup
    ];
  };

  testScript = ''
    import json
    from typing import Any

    PATCHED = ${if patched then "True" else "False"}
    results: dict[str, Any] = {"patched": PATCHED}

    # Outputs stay small: the driver's console transport truncates large ones.
    # Full logs are copied out through the shared directory instead.
    def sh(cmd):
        return machine.succeed(cmd)

    def snap(name):
        sh(f"python3 ${snapshot} /root/{name}.json /tnix /thome")

    def snapdiff(a, b):
        return json.loads(sh(f"python3 ${snapdiff} /root/{a}.json /root/{b}.json"))

    def bclone():
        sh("sync; zpool sync tank")
        out = sh("zpool get -Hp -o property,value bcloneused,bclonesaved tank")
        return {k: int(v) for k, v in (l.split() for l in out.splitlines())}

    def shared(ds, a, b):
        return json.loads(sh(f"python3 ${sharing} {ds} {a} {b}"))

    def count(path, pattern):
        return int(sh(f"grep -cE '{pattern}' {path} || true").strip() or 0)

    def zfs_dedup(tag, extra=""):
        rc, _ = machine.execute(
            f"strace -f -qq -e trace=ioctl -o /root/{tag}.strace "
            f"zfs-dedup -c /root/zd.redb {extra} > /root/{tag}.out 2> /root/{tag}.err")
        for f in ("err", "strace"):
            machine.copy_from_machine(f"/root/{tag}.{f}", "logs")
        st = f"/root/{tag}.strace"
        return {"exit": rc,
                "stderr": sh(f"grep -m 20 -E 'mismatches|FIDEDUPERANGE|force|error|skip|scanning|hashed|found' /root/{tag}.err || true").splitlines(),
                "fideduperange_ioctls": count(st, "FIDEDUPERANGE, [{]src_offset=[0-9]+, src_length=[0-9]+,"),
                "fideduperange_probe_ioctls": count(st, "FIDEDUPERANGE, [{]src_offset=0, src_length=131072,"),
                "ficlonerange_ioctls": count(st, "FICLONERANGE")}

    PAIRS = [
        ("tank/nix", "store/aaaa-pkg-1/lib/libfoo.so", "store/bbbb-pkg-2/lib/libfoo.so"),
        ("tank/nix", "store/aaaa-pkg-1/share/data.bin", "store/bbbb-pkg-2/share/data.bin"),
        ("tank/nix", "store/cccc-pkg-3/bin/tool", "store/dddd-pkg-4/bin/tool"),
        ("tank/nix", "store/cccc-pkg-3/bin/tool", "store/eeee-pkg-5/bin/tool"),
        ("tank/home", "u/x.bin", "u/y.bin"),
        ("tank/home", "u/suid-a", "u/suid-b"),
    ]
    SMALL = ("tank/nix", "store/aaaa-pkg-1/share/small", "store/bbbb-pkg-2/share/small")

    def sharing():
        return {f"{a} {b}": shared(ds, a, b) for ds, a, b in PAIRS + [SMALL]}

    machine.wait_for_unit("multi-user.target")
    sh("modprobe zfs")
    results["module"] = sh("cat /sys/module/zfs/version; cat /sys/module/zfs/srcversion; "
                           "readlink -f $(modinfo -n zfs); zfs version; uname -r; zfs-dedup -V").splitlines()
    sh("${setup} >&2")
    results["mounts"] = sh("findmnt -rno TARGET,SOURCE,FSTYPE,OPTIONS -t zfs").splitlines()

    # FIDEDUPERANGE directly, on a dataset destroyed afterwards.
    sh("zfs create -o mountpoint=legacy tank/probe && mkdir -p /tprobe && mount -t zfs tank/probe /tprobe"
       " && head -c 262144 /dev/urandom > /tprobe/s && dd if=/tprobe/s of=/tprobe/same status=none"
       " && head -c 262144 /dev/urandom > /tprobe/other && touch -d @1 /tprobe/same && sync")
    stat0 = sh("stat -c '%.9Y %.9Z' /tprobe/same").strip()
    results["ioctl_same"] = json.loads(sh("python3 ${fdr} /tprobe/s 262144 /tprobe/same"))
    results["ioctl_differs"] = json.loads(sh("python3 ${fdr} /tprobe/s 262144 /tprobe/other"))
    results["ioctl_same_mtime_ctime"] = [stat0, sh("stat -c '%.9Y %.9Z' /tprobe/same").strip()]
    sh("umount /tprobe && zfs destroy tank/probe")

    results["bclone_0"] = bclone()
    snap("before")
    results["files"] = snapdiff("before", "before")["regular_files"]

    # zfs-dedup without --force: the hosts' intended invocation.
    results["run1"] = zfs_dedup("run1")
    results["bclone_1"] = bclone()
    snap("after1")
    results["diff_1"] = snapdiff("before", "after1")
    results["sharing_1"] = sharing()

    if PATCHED:
        # A rerun finds everything already shared and must change nothing.
        results["run2"] = zfs_dedup("run2")
        results["bclone_2"] = bclone()
        snap("after2")
        results["diff_2"] = snapdiff("after1", "after2")
    else:
        results["run_force"] = zfs_dedup("run_force", "-f")
        results["bclone_force"] = bclone()
        snap("after_force")
        results["diff_force"] = snapdiff("after1", "after_force")
        results["sharing_force"] = sharing()

    # The pair changes between hash and clone.
    sh("mkdir -p /thome/differs && head -c 524288 /dev/urandom > /thome/differs/a"
       " && dd if=/thome/differs/a of=/thome/differs/b status=none && sync && zpool sync tank")
    results["bclone_race_0"] = bclone()
    results["race"] = json.loads(sh(f"python3 ${race} /thome/differs {'dedupe' if PATCHED else 'force'}"))
    machine.copy_from_machine("/root/race.log", "logs")
    results["bclone_race_1"] = bclone()
    results["race_sharing"] = shared("tank/home", "differs/a", "differs/b")

    print("RESULTS " + json.dumps(results, sort_keys=True))
    (machine.out_dir / "results.json").write_text(json.dumps(results, indent=1, sort_keys=True))

    # Assertions, after the results are printed.
    r: dict[str, Any] = results
    full = lambda s: "error" not in s and s["blocks"][0] == s["blocks"][1] and s["shared"] == s["blocks"][0] > 0
    if PATCHED:
        assert r["ioctl_same"] == {"errno": 0, "status": 0, "bytes_deduped": 262144}, r["ioctl_same"]
        assert r["ioctl_differs"]["errno"] == 0 and r["ioctl_differs"]["status"] == 1, r["ioctl_differs"]
        assert r["ioctl_same_mtime_ctime"][0] == r["ioctl_same_mtime_ctime"][1], r["ioctl_same_mtime_ctime"]
        assert r["run1"]["exit"] == 0, r["run1"]
        assert r["run1"]["fideduperange_ioctls"] > 0 and r["run1"]["ficlonerange_ioctls"] == 0, r["run1"]
        assert r["bclone_1"]["bclonesaved"] > r["bclone_0"]["bclonesaved"], (r["bclone_0"], r["bclone_1"])
        assert all(full(s) for k, s in r["sharing_1"].items() if "small" not in k), r["sharing_1"]
        assert r["diff_1"]["n"] == 0, r["diff_1"]
        assert r["run2"]["exit"] == 0 and r["diff_2"]["n"] == 0, (r["run2"], r["diff_2"])
        assert r["bclone_2"] == r["bclone_1"], (r["bclone_1"], r["bclone_2"])
        race: dict[str, Any] = r["race"]
        assert race["triggered"] == "FIDEDUPERANGE" and race["exit"] == 0, race
        assert race["after"][race["dst"].rsplit("/", 1)[1]] == race["written"], race
        assert any("0 B" in l and " 1 mismatches" in l for l in race["summary"]), race["summary"]
        assert r["race_sharing"].get("shared") == 0, r["race_sharing"]
        assert r["bclone_race_1"] == r["bclone_race_0"], (r["bclone_race_0"], r["bclone_race_1"])
    else:
        # ZFS has remap_file_range (for clones), so vfs_dedupe_file_range()
        # returns 0 and reports -EOPNOTSUPP in the target's status.
        assert r["ioctl_same"] == {"errno": 0, "status": -95, "bytes_deduped": 0}, r["ioctl_same"]
        assert r["run1"]["exit"] != 0, r["run1"]
        assert any("doesn't support FIDEDUPERANGE" in l for l in r["run1"]["stderr"]), r["run1"]
        assert r["bclone_1"] == r["bclone_0"] and r["diff_1"]["n"] == 0, (r["bclone_1"], r["diff_1"])
        assert r["run_force"]["exit"] == 0 and r["run_force"]["ficlonerange_ioctls"] > 0, r["run_force"]
        assert r["bclone_force"]["bclonesaved"] > r["bclone_1"]["bclonesaved"], r["bclone_force"]
        assert r["diff_force"]["store_mtime_changed"] > 0, r["diff_force"]
        assert set(r["diff_force"]["fields"]) <= {"mtime_ns", "ctime_ns"}, r["diff_force"]
        race: dict[str, Any] = r["race"]
        assert race["triggered"] == "FICLONERANGE" and race["exit"] == 0, race
        # The write made during the clone's window is lost.
        assert race["after"][race["dst"].rsplit("/", 1)[1]] != race["written"], race
  '';
}
