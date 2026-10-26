# Reproducer for openzfs/zfs#19185, the race that f1f96f5e7 (0006) closes,
# after the one in openzfs/zfs#19234: single-block 4 KiB files are written
# and synced, the dataset is remounted so their dbufs are uncached, a hole is
# punched over each file, and once the txg holding the frees starts to sync,
# every file is read back. The module's test-only dbuf_read_hole_delay
# widens the window between dbuf_read_hole()'s first BP_IS_HOLE() and
# dnode_block_freed(). Prints one JSON object.
import collections
import ctypes
import json
import os
import subprocess
import sys
import threading
import time

POOL, FS, MNT = "tank", "tank/race", "/race"
FILES, CYCLES, THREADS = (int(a) for a in sys.argv[1:4])
SIZE = 4096
ZERO = bytes(SIZE)
PUNCH = 0x02 | 0x01  # FALLOC_FL_PUNCH_HOLE | FALLOC_FL_KEEP_SIZE

libc = ctypes.CDLL(None, use_errno=True)
libc.fallocate.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_long, ctypes.c_long]


def run(*args):
    subprocess.run(args, check=True)


def syncing():
    """Whether a txg of the pool is syncing (history state W)."""
    with open(f"/proc/spl/kstat/zfs/{POOL}/txgs") as f:
        rows = [line.split() for line in f]
    head = next(i for i, r in enumerate(rows) if r[:3] == ["txg", "birth", "state"])
    return any(len(r) > 2 and r[2] == "W" for r in rows[head + 1 :])


totals = collections.Counter()
cycles = []
for c in range(CYCLES):
    d = f"{MNT}/c{c}"
    os.mkdir(d)
    paths = [f"{d}/{i}" for i in range(FILES)]
    for p in paths:
        with open(p, "wb") as f:
            f.write(os.urandom(SIZE))
    run("zpool", "sync", POOL)
    run("zfs", "unmount", FS)
    run("zfs", "mount", FS)
    for p in paths:
        fd = os.open(p, os.O_RDWR)
        try:
            if libc.fallocate(fd, PUNCH, 0, SIZE) != 0:
                e = ctypes.get_errno()
                raise OSError(e, os.strerror(e), p)
        finally:
            os.close(fd)
    syncer = subprocess.Popen(["zpool", "sync", POOL])
    deadline = time.monotonic() + 5
    seen = False
    while time.monotonic() < deadline:
        if syncing():
            seen = True
            break
    counts = collections.Counter()
    lock = threading.Lock()

    def reader(mine):
        local = collections.Counter()
        for p in mine:
            fd = os.open(p, os.O_RDONLY)
            try:
                data = os.pread(fd, SIZE, 0)
                local["zeros" if data == ZERO else "not_zeros"] += 1
            except OSError as e:
                local[f"errno_{e.errno}"] += 1
            finally:
                os.close(fd)
            local["reads"] += 1
        with lock:
            counts.update(local)

    threads = [threading.Thread(target=reader, args=(paths[k::THREADS],)) for k in range(THREADS)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    if syncer.wait() != 0:
        raise RuntimeError("zpool sync failed")
    totals.update(counts)
    cycles.append(dict(counts, cycle=c, saw_syncing=seen))

print(json.dumps({"totals": dict(totals), "cycles": cycles}))
