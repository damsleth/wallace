#!/usr/bin/env python3
"""Build a deterministic self-contained raw m1n1 Linux boot object.

This is a host-only packer. It reads ordinary files and writes one regular
file; it never opens a block device, APFS volume, or Boot Policy interface.
The output is intentionally re-verified by t6040-raw-object-verify.py.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import os
import struct
import tempfile
from pathlib import Path


M1N1_ALIGNMENT = 0x4000
RAW_ENTRY_POINT = 0x800
KERNEL_MAGIC = b"ARM\x64"
GZIP_MAGIC = b"\x1f\x8b"
XZ_MAGIC = b"\xfd7zXZ\x00"
FDT_MAGIC = b"\xd0\x0d\xfe\xed"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write(path: Path, data: bytes, *, force: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not force:
        raise FileExistsError(f"{path} exists (pass --force to replace it)")
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(tmp_name, 0o644)
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def kernel_member(data: bytes) -> bytes:
    if data.startswith(GZIP_MAGIC) or data.startswith(XZ_MAGIC):
        # Pre-compressed member used verbatim. XZ members must be
        # minilzlib-compatible: single-stream, single-block (-T1),
        # --check=crc32 (or none), no BCJ filter.
        return data
    if len(data) < 0x3C or data[0x38:0x3C] != KERNEL_MAGIC:
        raise ValueError("kernel is neither a gzip/xz member nor an ARM64 Image")
    image_size = struct.unpack_from("<Q", data, 0x10)[0]
    if not image_size or len(data) > image_size:
        raise ValueError(
            f"invalid ARM64 Image size: file={len(data)} header={image_size}"
        )
    return gzip.compress(data, compresslevel=9, mtime=0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--m1n1", required=True, type=Path)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--dtb", required=True, type=Path)
    parser.add_argument("--initramfs", required=True, type=Path)
    parser.add_argument("--bootargs", required=True)
    parser.add_argument(
        "--kernel-output",
        type=Path,
        help="also save the exact compressed kernel member",
    )
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    if "\n" in args.bootargs or "\0" in args.bootargs:
        parser.error("--bootargs cannot contain newline or NUL")

    m1n1 = args.m1n1.read_bytes()
    if len(m1n1) % M1N1_ALIGNMENT:
        raise ValueError(f"m1n1 size {len(m1n1)} is not 16 KiB aligned")
    if (
        len(m1n1) <= RAW_ENTRY_POINT + 4
        or m1n1[RAW_ENTRY_POINT:RAW_ENTRY_POINT + 4] == b"\0\0\0\0"
    ):
        raise ValueError("m1n1 does not contain a nonzero raw entry at 0x800")

    kernel = kernel_member(args.kernel.read_bytes())
    dtb = args.dtb.read_bytes()
    if len(dtb) < 8 or not dtb.startswith(FDT_MAGIC):
        raise ValueError("DTB does not begin with the FDT magic")
    if struct.unpack_from(">I", dtb, 4)[0] != len(dtb):
        raise ValueError("DTB totalsize does not equal file size")

    initramfs = args.initramfs.read_bytes()
    if not (initramfs.startswith(GZIP_MAGIC) or initramfs.startswith(XZ_MAGIC)):
        raise ValueError("initramfs must be a gzip or xz member")

    variable = f"chosen.bootargs={args.bootargs}\n".encode("ascii")
    output = m1n1 + variable + kernel + dtb + initramfs + b"\0" * 4

    if args.kernel_output:
        atomic_write(args.kernel_output, kernel, force=args.force)
    atomic_write(args.output, output, force=args.force)

    print(f"object  {len(output):9d} {sha256(output)} {args.output}")
    print(f"m1n1   {len(m1n1):9d} {sha256(m1n1)} {args.m1n1}")
    print(f"kernel {len(kernel):9d} {sha256(kernel)}")
    print(f"dtb    {len(dtb):9d} {sha256(dtb)} {args.dtb}")
    print(f"initrd {len(initramfs):9d} {sha256(initramfs)} {args.initramfs}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
