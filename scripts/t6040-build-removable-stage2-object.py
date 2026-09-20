#!/usr/bin/env python3
"""Build the deterministic iBoot object for the T6040 removable-media stage 2."""

import argparse
import hashlib
import json
import os
import struct
import tempfile
from pathlib import Path


ALIGN = 16 * 1024
ARM64_MAGIC = b"ARM\x64"
FDT_MAGIC = 0xD00DFEED


def digest(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def read(path: Path) -> bytes:
    try:
        return path.read_bytes()
    except OSError as exc:
        raise SystemExit(f"cannot read {path}: {exc}") from exc


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--m1n1", required=True, type=Path)
    parser.add_argument("--dtb", required=True, type=Path)
    parser.add_argument("--u-boot", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--source-date-epoch", required=True, type=int)
    args = parser.parse_args()

    m1n1 = read(args.m1n1)
    dtb = read(args.dtb)
    uboot = read(args.u_boot)

    if len(m1n1) % ALIGN:
        raise SystemExit(f"m1n1 is not 16 KiB aligned: {len(m1n1)} bytes")
    if len(dtb) < 8 or struct.unpack_from(">I", dtb)[0] != FDT_MAGIC:
        raise SystemExit("DTB has no flattened-device-tree magic")
    dtb_size = struct.unpack_from(">I", dtb, 4)[0]
    if dtb_size != len(dtb):
        raise SystemExit(f"DTB totalsize {dtb_size} does not equal file size {len(dtb)}")
    if len(uboot) < 64 or uboot[56:60] != ARM64_MAGIC:
        raise SystemExit("U-Boot payload has no arm64 Image header")
    text_offset, runtime_size = struct.unpack_from("<QQ", uboot, 8)
    if text_offset != 0:
        raise SystemExit(f"U-Boot text offset must be zero, got 0x{text_offset:x}")
    if runtime_size < len(uboot):
        raise SystemExit(
            f"U-Boot runtime size {runtime_size} is smaller than file size {len(uboot)}"
        )

    object_blob = m1n1 + dtb + uboot
    object_blob += bytes(runtime_size - len(uboot))
    object_blob += bytes((-len(object_blob)) % ALIGN)

    manifest = {
        "schema": 1,
        "kind": "t6040-removable-stage2-iboot-object",
        "source_date_epoch": args.source_date_epoch,
        "iboot_load_address": "0x800",
        "alignment": ALIGN,
        "layout": ["m1n1", "stage2-dtb", "u-boot-arm64-image", "zero-padding"],
        "components": {
            "m1n1": {"size": len(m1n1), "sha256": digest(m1n1)},
            "dtb": {"size": len(dtb), "sha256": digest(dtb)},
            "u_boot": {
                "file_size": len(uboot),
                "runtime_size": runtime_size,
                "sha256": digest(uboot),
            },
        },
        "object": {"size": len(object_blob), "sha256": digest(object_blob)},
    }

    for path, data in (
        (args.output, object_blob),
        (args.manifest, (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()),
    ):
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


if __name__ == "__main__":
    main()
