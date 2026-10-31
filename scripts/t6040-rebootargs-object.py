#!/usr/bin/env python3
"""Rebuild an existing raw m1n1 boot object with different bootargs.

Splits OBJECT into its m1n1 stage and its compressed kernel member, using the
DTB and initramfs it was built from to find the boundaries. The pieces are
written to OUTDIR, and t6040-build-raw-object.py is then used to rebuild. Run it
once with the object's own bootargs first: the result must be byte-identical to
OBJECT, or the split is wrong (ticket 5024).

    t6040-rebootargs-object.py OBJECT --dtb board.dtb --initramfs initramfs.cpio.gz \
        --outdir DIR [--bootargs '<new args>' | --prepend 'nr_cpus=1'] [--replace-dtb new.dtb]
        [--replace-m1n1 m1n1.bin]
"""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
from pathlib import Path

VAR = b"chosen.bootargs="


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("object", type=Path)
    p.add_argument("--dtb", required=True, type=Path)
    p.add_argument("--initramfs", required=True, type=Path)
    p.add_argument("--outdir", required=True, type=Path)
    g = p.add_mutually_exclusive_group()
    g.add_argument("--bootargs", help="replace the bootargs")
    g.add_argument("--prepend", help="prepend these args to the existing bootargs")
    p.add_argument("--name", default="object.bin", help="output object file name")
    p.add_argument("--replace-dtb", type=Path,
                   help="rebuild with this DTB instead of --dtb (a DT-only variant)")
    p.add_argument("--replace-m1n1", type=Path,
                   help="rebuild with this m1n1.bin instead of the one inside OBJECT")
    a = p.parse_args()

    obj = a.object.read_bytes()
    dtb = a.dtb.read_bytes()
    initramfs = a.initramfs.read_bytes()
    start = obj.index(VAR)
    if start % 0x4000:
        sys.exit(f"bootargs variable at {start:#x} is not 16 KiB aligned")
    nl = obj.index(b"\n", start) + 1
    old = obj[start + len(VAR):nl - 1].decode("ascii")
    dtb_at = obj.index(dtb, nl)
    if obj[dtb_at + len(dtb):dtb_at + len(dtb) + len(initramfs)] != initramfs:
        sys.exit("initramfs does not follow the DTB in the object")

    a.outdir.mkdir(parents=True, exist_ok=True)
    m1n1, kernel = a.outdir / "m1n1.bin", a.outdir / "Image.gz"
    m1n1.write_bytes(a.replace_m1n1.read_bytes() if a.replace_m1n1 else obj[:start])
    kernel.write_bytes(obj[nl:dtb_at])
    new = a.bootargs if a.bootargs is not None else (
        f"{a.prepend} {old}" if a.prepend else old)
    (a.outdir / "bootargs.txt").write_text(new + "\n")

    builder = Path(__file__).with_name("t6040-build-raw-object.py")
    out = a.outdir / a.name
    subprocess.run([sys.executable, "-I", str(builder), str(out), "--m1n1", str(m1n1),
                    "--kernel", str(kernel), "--dtb", str(a.replace_dtb or a.dtb),
                    "--initramfs", str(a.initramfs), "--bootargs", new, "--force"],
                   check=True, stdout=subprocess.DEVNULL)
    h = hashlib.sha256(out.read_bytes()).hexdigest()
    print(f"old bootargs: {old}")
    print(f"new bootargs: {new}")
    print(f"{h}  {out}")
    if new == old and not a.replace_dtb and not a.replace_m1n1 and out.read_bytes() != obj:
        sys.exit("rebuild with unchanged bootargs differs from the input object")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
