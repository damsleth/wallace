#!/usr/bin/env python3
"""Recover the PREVIOUS boot's m1n1/Linux log text from RAM after a failed boot.

RAM survives a warm reset. m1n1 allocates its stage-2 log buffer at the top of RAM
(src/kboot.c:2751, top_of_memory_alloc) during kboot and registers it as a console
iodev, so if a failing boot reached kboot, its tail output is still in RAM on the
next boot.

Run with ANY payload-free object enrolled and the machine at `Running proxy`
(read-only). Scans the top region of RAM for printable runs and reports matches for
telltale markers.

Usage: M1N1DEVICE=/dev/cu.usbmodemJ22GYCN4YG1 venv/bin/python <this> [--mib 4]
"""
import argparse, re, sys
sys.path.insert(0, "/Users/damsleth/Code/m1n1/proxyclient")
from m1n1.setup import *  # noqa

MARKERS = [b"Uncompressing", b"XZ decode", b"uncompressed to", b"Preparing to boot",
           b"Vectoring to next stage", b"Valid payload found", b"Checking for payloads",
           b"Linux version", b"Kernel panic", b"Unable to mount", b"SError",
           b"Unhandled exception", b"initramfs", b"rdinit"]

ap = argparse.ArgumentParser()
ap.add_argument("--mib", type=int, default=4, help="how many MiB below top of RAM to scan")
args = ap.parse_args()

top = u.ba.phys_base + u.ba.mem_size
print("phys_base = 0x%x  mem_size = 0x%x  -> top of RAM = 0x%x" % (u.ba.phys_base, u.ba.mem_size, top))
print("scanning %d MiB below top of RAM for previous-boot log text\n" % args.mib)

CHUNK = 0x10000
found = {}
printable = re.compile(rb"[ -~\n\r\t]{24,}")
start = top - args.mib * 1024 * 1024
addr = start
while addr < top:
    try:
        d = iface.readmem(addr, CHUNK)
    except Exception as e:
        print("  read failed at 0x%x: %s" % (addr, e)); break
    for m in MARKERS:
        if m in d:
            off = d.find(m)
            found.setdefault(m, (addr + off, d))
    addr += CHUNK

if not found:
    print("NO log markers found in the scanned region.")
    print("=> the failing boot left no kboot-stage log in RAM, i.e. it very likely")
    print("   died BEFORE kboot (during payload decompression or earlier).")
else:
    print("MARKERS FOUND (previous boot got at least this far):")
    for m, (a, blk) in sorted(found.items(), key=lambda kv: kv[1][0]):
        print("  0x%x  %s" % (a, m.decode()))
    # dump the largest printable run near the first hit for context
    first = min(v[0] for v in found.values())
    base = first & ~0xFFFF
    d = iface.readmem(base, CHUNK)
    runs = sorted(printable.findall(d), key=len, reverse=True)[:6]
    print("\ncontext (longest printable runs in that 64 KiB block):")
    for r in runs:
        txt = r.decode("ascii", "replace").strip()
        if txt:
            print("  | " + txt.replace("\n", "\n  | ")[:600])
