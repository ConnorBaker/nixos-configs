# A build's memory, for the agent-memory test. Run as a builder, or as a
# transient unit's process (no $out: SLICEFILL_READY names a file to
# write once the memory is held, then it sleeps SLICEFILL_HOLD seconds
# and reads the pages back unless SLICEFILL_READBACK is 0):
#   slicefill.py hold MODE MIB   hold MIB MiB of MODE pages, read every
#                                page back, write $out
#   slicefill.py grow MODE       grow by 16 MiB of MODE pages until killed
# MODE, per 4 KiB page: comp, 1 KiB random and 3 KiB zeros (zstd stores
# it in about a quarter); tiny, 16 random bytes and zeros (zswap stores
# it in a few dozen bytes, its metadata in more); rand, 4 KiB random
# (incompressible); zero, 4 KiB of written zeros (same-filled: a swap
# slot and no RAM). No page is same-filled but in zero; the pages repeat
# one 1 MiB block, which neither zram nor zswap deduplicates.
import os
import sys
import time


def block(mode):
    if mode == "zero":
        return bytes(1 << 20)
    if mode == "rand":
        return None
    r = {"comp": 1024, "tiny": 16}[mode]
    return b"".join(os.urandom(r) + bytes(4096 - r) for _ in range(256))


def chunk(blk, mib):
    return bytearray(os.urandom(mib << 20)) if blk is None else bytearray(blk * mib)


what, mode = sys.argv[1], sys.argv[2]
blk = block(mode)
if what == "grow":
    held = []
    while True:
        held.append(chunk(blk, 16))
        print(f"grown to {16 * len(held)} MiB", file=sys.stderr, flush=True)
mib = int(sys.argv[3])
held = [chunk(blk, 1) for _ in range(mib)]
print(f"held {mib} MiB ({mode})", file=sys.stderr, flush=True)
out = os.environ.get("out")
if not out:
    with open(os.environ["SLICEFILL_READY"], "w") as f:
        f.write(f"{mib} {mode}\n")
    time.sleep(float(os.environ.get("SLICEFILL_HOLD", "0")))
    if os.environ.get("SLICEFILL_READBACK") == "0":
        sys.exit(0)
s = sum(c[i] for c in held for i in range(0, len(c), 4096))
print(f"read back {mib} MiB ({mode})", file=sys.stderr, flush=True)
if out:
    with open(out, "w") as f:
        f.write(f"{mib} {mode} {s}\n")
