#!/usr/bin/env python3
"""Strict host-only verifier for the T6040 Alpine B0 initramfs."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import stat
from pathlib import Path


def aligned(value: int) -> int:
    return (value + 3) & ~3


def parse_newc(blob: bytes) -> dict[str, tuple[int, bytes]]:
    entries: dict[str, tuple[int, bytes]] = {}
    offset = 0
    while True:
        if blob[offset:offset + 6] != b"070701":
            raise ValueError(f"bad newc magic at 0x{offset:x}")
        fields = [
            int(blob[offset + 6 + i * 8:offset + 14 + i * 8], 16)
            for i in range(13)
        ]
        mode = fields[1]
        size = fields[6]
        name_size = fields[11]
        name_start = offset + 110
        name_end = name_start + name_size
        if name_size < 1 or blob[name_end - 1] != 0:
            raise ValueError(f"invalid name at 0x{offset:x}")
        name = blob[name_start:name_end - 1].decode()
        data_start = aligned(name_end)
        data_end = data_start + size
        data = blob[data_start:data_end]
        offset = aligned(data_end)
        if name == "TRAILER!!!":
            break
        if name in entries:
            raise ValueError(f"duplicate archive entry: {name}")
        entries[name] = (mode, data)
    if any(blob[offset:]):
        raise ValueError("nonzero data after newc trailer")
    return entries


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--sha256")
    args = parser.parse_args()

    archive = args.archive.read_bytes()
    digest = hashlib.sha256(archive).hexdigest()
    if args.sha256 and digest != args.sha256:
        raise ValueError(f"SHA mismatch: {digest} != {args.sha256}")
    entries = parse_newc(gzip.decompress(archive))

    required = {
        "./sbin/init",
        "./sbin/openrc",
        "./etc/runlevels/sysinit/procfs",
        "./etc/runlevels/sysinit/sysfs",
        "./etc/runlevels/default/t6040-watchdog",
        "./etc/runlevels/default/t6040-health-report",
        "./usr/local/sbin/t6040-b0-autologin",
        "./usr/local/sbin/t6040-b0-ttydc0-console",
    }
    missing = required - entries.keys()
    if missing:
        raise ValueError(f"missing entries: {sorted(missing)}")

    block_nodes = [
        name for name, (mode, _) in entries.items() if stat.S_ISBLK(mode)
    ]
    if block_nodes:
        raise ValueError(f"block nodes present: {block_nodes}")

    forbidden = {
        "./etc/runlevels/default/networking",
        "./etc/runlevels/boot/networking",
        "./etc/resolv.conf",
        "./etc/network/interfaces",
    }
    present = forbidden & entries.keys()
    if present:
        raise ValueError(f"network configuration present: {sorted(present)}")

    shadow = entries["./etc/shadow"][1].decode()
    if not shadow.startswith("root:!:"):
        raise ValueError("root password is not locked")
    arch = entries["./etc/apk/arch"][1]
    if arch.strip() != b"aarch64":
        raise ValueError(f"unexpected APK architecture: {arch!r}")

    print(f"PASS sha256={digest} entries={len(entries)} block_nodes=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
