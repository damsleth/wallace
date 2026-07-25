#!/usr/bin/env python3
"""Attach inside m1n1's early-proxy window on a looping payload object and measure.

Read-only. Answers the question the elimination table leaves: is the payload intact
in RAM (so the failure is in decompression/handoff), or corrupted (so it is a load
or overlap problem)?

Run while the target loops with a 60 s-window payload object enrolled. Poll for the
gadget first, then this connects and reports:
  1. m1n1 base, top_of_kernel_data, heap base, and where the payload extent ends;
  2. each payload member re-hashed FROM TARGET RAM and compared to its known hash.

Usage: M1N1DEVICE=/dev/cu.usbmodemJ22GYCN4YG1 venv/bin/python <this>
"""
import hashlib, sys
sys.path.insert(0, "/Users/damsleth/Code/m1n1/proxyclient")
from m1n1.setup import *  # noqa

PAYLOAD_OFF = 0x10C000
# (name, offset within object, length, expected sha256) — from the strict verifier
MEMBERS = [
    ("chosen.bootargs", 0x10C000,      145,
     "3659a0da253c70590f30fb39a3455e2aa78213dda634acfa9e9d8eff916ebc27"),
    ("kernel (xz)",     0x10C091,  4909804,
     "efba5999aa5f598de58bf6a272f9f2eed4ccad38a15e12b813a66dec426d7b69"),
    ("dtb",             0x5BAB7D,    51659,
     "2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce"),
    ("initramfs (xz)",  0x5C7548,  3395816,
     "d7fcc795f62e367dc7d1cdb0bee40311629f2cc742489a2ab979b211e1b28ab4"),
]
OBJ_END = 0x904634

print("=== layout ===")
print("  m1n1 base          = 0x%x" % u.base)
print("  payload start      = 0x%x" % (u.base + PAYLOAD_OFF))
print("  object end         = 0x%x  (+0x%x, %.2f MiB)" % (u.base + OBJ_END, OBJ_END, OBJ_END/1048576))
tokd = u.ba.top_of_kernel_data
print("  top_of_kernel_data = 0x%x  (+0x%x, %.2f MiB)" % (tokd, tokd - u.base, (tokd-u.base)/1048576))
print("  heap starts at top_of_kernel_data (src/heapblock.c) -> %s payload extent"
      % ("ABOVE" if tokd >= u.base + OBJ_END else "*** INSIDE ***"))
print("  mem_size           = 0x%x" % u.ba.mem_size)

print("\n=== payload members re-hashed from target RAM ===")
allok = True
for name, off, length, want in MEMBERS:
    h = hashlib.sha256()
    addr = u.base + off
    remaining = length
    while remaining:
        n = min(remaining, 0x10000)
        h.update(iface.readmem(addr, n))
        addr += n
        remaining -= n
    got = h.hexdigest()
    ok = got == want
    allok &= ok
    print("  %-16s %-9s %s" % (name, "OK" if ok else "MISMATCH", got[:32]))
    if not ok:
        print("                   expected %s" % want[:32])

print()
print("VERDICT: payload in RAM is %s" % ("BYTE-INTACT -> failure is in decompression/DT/handoff, not loading"
                                        if allok else "CORRUPTED -> a load/overlap problem after all"))
