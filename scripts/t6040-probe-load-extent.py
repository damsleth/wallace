#!/usr/bin/env python3
"""Measure how much of an enrolled raw boot object iBoot actually loads into RAM.

Read-only. Requires the graded probe object
(linux-build-out/probe-graded-20M.bin, sha256 3bf31cde...) to be ENROLLED and the
machine sitting at `Running proxy`. Each 64 KiB block from offset 0x10c000 onward
begins with b"WLOFS" + its own offset as u64 LE, so a single memory read tells us
whether that offset was loaded (stamp matches), is stale RAM (garbage), or is zero.

Usage: M1N1DEVICE=/dev/cu.usbmodemJ22GYCN4YG1 venv/bin/python <this>
"""
import sys
sys.path.insert(0, "/Users/damsleth/Code/m1n1/proxyclient")
from m1n1.setup import *  # noqa

BASE_OFF = 0x10C000
STEP = 0x10000
LIMIT = 20 * 1024 * 1024

def classify(data, want_off):
    if data[:5] == b"WLOFS":
        got = int.from_bytes(data[5:13], "little")
        return "LOADED" if got == want_off else f"LOADED-but-wrong-off(0x{got:x})"
    if data == bytes(len(data)):
        return "zero"
    return "stale/other"

print("m1n1 base = 0x%x   top_of_kernel_data = 0x%x (base+0x%x)"
      % (u.base, u.ba.top_of_kernel_data, u.ba.top_of_kernel_data - u.base))
print()
last_loaded = None
off = BASE_OFF
while off < LIMIT:
    d = iface.readmem(u.base + off, 16)
    verdict = classify(d, off)
    mark = ""
    if off <= 0x77C000 < off + STEP:
        mark = "   <-- 0x77c000 (top_of_kernel_data delta)"
    if verdict == "LOADED":
        last_loaded = off
    else:
        print("  0x%08x  %-28s%s" % (off, verdict, mark))
        # print a couple past the boundary then stop scanning densely
        if last_loaded is not None:
            break
    off += STEP if off < 0x100000 else 0x40000   # dense early, coarser later

print()
if last_loaded is not None:
    print("HIGHEST LOADED OFFSET SEEN: 0x%x (%.2f MiB)" % (last_loaded, last_loaded / 1048576))
    print("0x77c000 = %.2f MiB" % (0x77C000 / 1048576))
else:
    print("no stamped block was loaded at all")
