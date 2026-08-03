#!/usr/bin/env python3
"""Build a self-describing graded probe object to measure iBoot's load extent.

Ticket 156. The probe is a payload-free m1n1 loader followed by filler in which every
64 KiB-aligned offset carries its own address, so a single memory read tells you whether
that offset was loaded. Reading it back is scripts/t6040-probe-load-extent.py, which
steps 0x10000 from 0x10C000 and expects b"WLOFS" + the offset as u64 LE.

Layout (reverse-engineered byte-for-byte from the live-proven probe-graded-256M.bin,
which has 4080 valid stamps, filler 0x5a, and a final block truncated to EOF):

    [0 .. len(m1n1))            the exact m1n1 loader, unmodified
    [0x10C000 .. size)          0x5a filler, with b"WLOFS" + u64le(offset) written at
                                every offset 0x10C000 + k*0x10000 that has room

m1n1 scans for a payload, finds the "WLOF" stamp, prints "Unknown payload ... magic:
574c4f46", concludes "No valid payload found" and drops to `Running proxy` — which is
exactly what the read-back needs, so the stamps are deliberately not a valid payload.

This is a host-only packer: it reads ordinary files and writes one regular file. It never
opens a block device, APFS volume, or Boot Policy interface. ENROLLING the result is a
maintainer action (kmutil is 1TR-only).

An enrolled object's total size must be a whole multiple of 16 KiB or iBoot never enters
m1n1 at all (ticket 129), so sizes are given in whole MiB and asserted here.
"""
import argparse
import hashlib
import pathlib
import struct
import sys

STAMP_MAGIC = b"WLOFS"
STAMP_BASE = 0x10C000
STAMP_STEP = 0x10000
FILLER = 0x5A
ALIGNMENT = 0x4000  # 16 KiB Apple Silicon page size
STAMP_LEN = len(STAMP_MAGIC) + 8


def build(m1n1: bytes, total_size: int) -> tuple[bytearray, int]:
    if total_size <= len(m1n1):
        raise ValueError(
            f"target size {total_size} is not larger than the m1n1 loader ({len(m1n1)})"
        )
    if total_size % ALIGNMENT:
        raise ValueError(
            f"target size {total_size} is not a multiple of 16 KiB "
            f"(short by {ALIGNMENT - total_size % ALIGNMENT} bytes)"
        )
    if len(m1n1) > STAMP_BASE:
        raise ValueError(
            f"m1n1 is {len(m1n1)} bytes, which overruns the stamp base {STAMP_BASE:#x}"
        )

    out = bytearray(m1n1)
    out += bytes([FILLER]) * (total_size - len(m1n1))

    stamps = 0
    off = STAMP_BASE
    while off + STAMP_LEN <= total_size:
        out[off : off + STAMP_LEN] = STAMP_MAGIC + struct.pack("<Q", off)
        stamps += 1
        off += STAMP_STEP
    return out, stamps


def selfcheck(data: bytes, stamps_expected: int) -> None:
    """Re-read the built object the way the reader will, and prove every stamp is right."""
    if len(data) % ALIGNMENT:
        raise ValueError("built object is not 16 KiB aligned")
    seen = 0
    off = STAMP_BASE
    while off + STAMP_LEN <= len(data):
        blob = data[off : off + STAMP_LEN]
        if blob[: len(STAMP_MAGIC)] != STAMP_MAGIC:
            raise ValueError(f"missing stamp at {off:#x}")
        got = struct.unpack("<Q", blob[len(STAMP_MAGIC) :])[0]
        if got != off:
            raise ValueError(f"stamp at {off:#x} carries wrong offset {got:#x}")
        seen += 1
        off += STAMP_STEP
    if seen != stamps_expected:
        raise ValueError(f"stamp count mismatch: wrote {stamps_expected}, read {seen}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--m1n1", type=pathlib.Path, required=True,
                    help="payload-free m1n1 loader that reaches `Running proxy`")
    ap.add_argument("--mib", type=int, required=True, help="total object size in whole MiB")
    ap.add_argument("output", type=pathlib.Path)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if args.output.exists() and not args.force:
        print(f"refusing to overwrite {args.output} (use --force)", file=sys.stderr)
        return 1

    m1n1 = args.m1n1.read_bytes()
    total = args.mib * 1024 * 1024
    data, stamps = build(m1n1, total)
    selfcheck(bytes(data), stamps)
    args.output.write_bytes(data)

    print(f"probe    {len(data):10d} {hashlib.sha256(data).hexdigest()} {args.output}")
    print(f"  size   {args.mib} MiB = {len(data) // ALIGNMENT} x 16 KiB (aligned)")
    print(f"  m1n1   {len(m1n1):10d} {hashlib.sha256(m1n1).hexdigest()} {args.m1n1}")
    print(f"  stamps {stamps} at {STAMP_BASE:#x} + k*{STAMP_STEP:#x}, filler {FILLER:#02x}")
    print(f"  read back with: PROBE_LIMIT_MIB={args.mib} "
          f"M1N1DEVICE=<dev> venv/bin/python scripts/t6040-probe-load-extent.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
