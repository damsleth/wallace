#!/usr/bin/env python3
"""Inspect and verify a self-contained raw m1n1 Linux boot object.

The raw format has no outer container. It is the exact m1n1.bin prefix followed
by the payload stream understood by m1n1/src/payload.c. For the Wallace B0 path
the required order is:

    chosen.bootargs=<...>\n
    Image.gz
    board.dtb
    initramfs.cpio.gz
    four or more zero bytes

This tool is host-only. It never opens a device, APFS volume, or Boot Policy.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import lzma
import struct
import sys
import zlib
from dataclasses import asdict, dataclass
from pathlib import Path


RAW_ENTRY_POINT = 0x800
M1N1_ALIGNMENT = 0x4000
MAX_OBJECT_SIZE = 64 * 1024 * 1024
MAX_COMPRESSED_EXPANSION = 1024 * 1024 * 1024
MAX_KERNEL_RESERVE = 512 * 1024 * 1024
MAX_INITRAMFS_EXPANDED = 256 * 1024 * 1024
MAX_DTB_SIZE = 2 * 1024 * 1024
DTB_GROWTH_RESERVE = 6 * M1N1_ALIGNMENT

GZIP_MAGIC = b"\x1f\x8b"
XZ_MAGIC = b"\xfd7zXZ\x00"
FDT_MAGIC = b"\xd0\x0d\xfe\xed"
KERNEL_MAGIC = b"ARM\x64"
CPIO_MAGICS = (b"070701", b"070702")
SIGNATURE_MAGIC = b"m1n1_sig"
INITRAMFS_MAGIC = b"m1n1_initramfs"
LOGO_MAGIC = b"m1n1_logo_256128"
LOGO_SIZE = 4 * ((256 * 256) + (128 * 128))


class VerificationError(ValueError):
    """The object does not satisfy the m1n1/Wallace payload contract."""


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@dataclass
class Record:
    role: str
    encoding: str
    offset: int
    size: int
    sha256: str
    expanded_size: int | None = None
    expanded_sha256: str | None = None
    runtime_reserve: int = 0


def classify_expanded(data: bytes) -> tuple[str, int]:
    if len(data) >= 0x3C and data[0x38:0x3C] == KERNEL_MAGIC:
        image_size = struct.unpack_from("<Q", data, 0x10)[0]
        if not image_size:
            raise VerificationError("kernel header has zero image_size")
        if len(data) > image_size:
            raise VerificationError(
                f"kernel file ({len(data)} bytes) exceeds header image_size "
                f"({image_size} bytes)"
            )
        if image_size > MAX_KERNEL_RESERVE:
            raise VerificationError(
                f"kernel runtime reserve {image_size} exceeds B0 limit "
                f"{MAX_KERNEL_RESERVE}"
            )
        return "kernel", image_size

    if data.startswith(FDT_MAGIC):
        if len(data) < 8:
            raise VerificationError("truncated FDT header")
        total = struct.unpack_from(">I", data, 4)[0]
        if total != len(data):
            raise VerificationError(
                f"expanded FDT totalsize {total} does not equal member size {len(data)}"
            )
        if total > MAX_DTB_SIZE:
            raise VerificationError(f"FDT size {total} exceeds B0 limit {MAX_DTB_SIZE}")
        return "dtb", total + DTB_GROWTH_RESERVE

    if data.startswith(CPIO_MAGICS):
        if len(data) > MAX_INITRAMFS_EXPANDED:
            raise VerificationError(
                f"initramfs expands to {len(data)} bytes, over B0 limit "
                f"{MAX_INITRAMFS_EXPANDED}"
            )
        return "initramfs", len(data)

    raise VerificationError(
        f"compressed member expands to unknown magic {data[:8].hex()}"
    )


def decompress_member(data: bytes, encoding: str) -> tuple[bytes, int]:
    if encoding == "gzip":
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        try:
            expanded = decoder.decompress(data, MAX_COMPRESSED_EXPANSION + 1)
            expanded += decoder.flush()
        except zlib.error as exc:
            raise VerificationError(f"invalid gzip member: {exc}") from exc
        if len(expanded) > MAX_COMPRESSED_EXPANSION:
            raise VerificationError("gzip member exceeds m1n1's 1 GiB decode limit")
        if not decoder.eof:
            raise VerificationError("truncated gzip member or expansion over 1 GiB")
        consumed = len(data) - len(decoder.unused_data)
    elif encoding == "xz":
        decoder = lzma.LZMADecompressor(format=lzma.FORMAT_XZ)
        try:
            expanded = decoder.decompress(data, max_length=MAX_COMPRESSED_EXPANSION + 1)
        except lzma.LZMAError as exc:
            raise VerificationError(f"invalid XZ member: {exc}") from exc
        if len(expanded) > MAX_COMPRESSED_EXPANSION:
            raise VerificationError("XZ member exceeds m1n1's 1 GiB decode limit")
        if not decoder.eof:
            raise VerificationError("truncated XZ member or expansion over 1 GiB")
        consumed = len(data) - len(decoder.unused_data)
    else:
        raise AssertionError(encoding)

    if consumed <= 0:
        raise VerificationError(f"{encoding} decoder consumed no input")
    return expanded, consumed


def parse_variable(data: bytes, offset: int) -> tuple[str, str, int] | None:
    name_end = data.find(b"=", offset, min(len(data), offset + 65))
    if name_end < 0:
        return None
    line_end = data.find(b"\n", name_end + 1, min(len(data), name_end + 1026))
    if line_end < 0:
        raise VerificationError(f"unterminated variable at offset {offset:#x}")
    try:
        name = data[offset:name_end].decode("ascii")
        value = data[name_end + 1:line_end].decode("ascii")
    except UnicodeDecodeError as exc:
        raise VerificationError(f"non-ASCII variable at offset {offset:#x}") from exc
    if not name:
        raise VerificationError(f"empty variable name at offset {offset:#x}")
    return name, value, line_end + 1


def parse_payload_stream(data: bytes, start: int) -> tuple[list[Record], dict[str, str]]:
    records: list[Record] = []
    variables: dict[str, str] = {}
    offset = start

    while offset < len(data):
        remaining = data[offset:]

        if remaining.startswith(b"\0\0\0\0"):
            if any(remaining):
                raise VerificationError(
                    f"non-zero data follows terminator at offset {offset:#x}"
                )
            records.append(
                Record("terminator", "zero", offset, len(remaining), sha256(remaining))
            )
            offset = len(data)
            break

        if remaining.startswith(GZIP_MAGIC) or remaining.startswith(XZ_MAGIC):
            encoding = "gzip" if remaining.startswith(GZIP_MAGIC) else "xz"
            expanded, consumed = decompress_member(remaining, encoding)
            role, runtime_reserve = classify_expanded(expanded)
            member = remaining[:consumed]
            records.append(
                Record(
                    role,
                    encoding,
                    offset,
                    consumed,
                    sha256(member),
                    len(expanded),
                    sha256(expanded),
                    runtime_reserve,
                )
            )
            offset += consumed
            continue

        if remaining.startswith(FDT_MAGIC):
            if len(remaining) < 8:
                raise VerificationError(f"truncated FDT at offset {offset:#x}")
            total = struct.unpack_from(">I", remaining, 4)[0]
            if total < 40 or total > len(remaining):
                raise VerificationError(
                    f"invalid/truncated FDT totalsize {total} at offset {offset:#x}"
                )
            if total > MAX_DTB_SIZE:
                raise VerificationError(f"FDT size {total} exceeds {MAX_DTB_SIZE}")
            member = remaining[:total]
            records.append(
                Record(
                    "dtb",
                    "raw",
                    offset,
                    total,
                    sha256(member),
                    total,
                    sha256(member),
                    total + DTB_GROWTH_RESERVE,
                )
            )
            offset += total
            continue

        if remaining.startswith(INITRAMFS_MAGIC):
            header_size = len(INITRAMFS_MAGIC) + 4
            if len(remaining) < header_size:
                raise VerificationError(
                    f"truncated initramfs wrapper at offset {offset:#x}"
                )
            payload_size = struct.unpack_from("<I", remaining, len(INITRAMFS_MAGIC))[0]
            total = header_size + payload_size
            if total > len(remaining):
                raise VerificationError(
                    f"initramfs wrapper at {offset:#x} declares {payload_size} bytes"
                )
            payload = remaining[header_size:total]
            if not payload.startswith(CPIO_MAGICS):
                raise VerificationError("wrapped initramfs is not a newc/crc cpio archive")
            if payload_size > MAX_INITRAMFS_EXPANDED:
                raise VerificationError("wrapped initramfs exceeds B0 expansion limit")
            member = remaining[:total]
            records.append(
                Record(
                    "initramfs",
                    "m1n1-wrapper",
                    offset,
                    total,
                    sha256(member),
                    payload_size,
                    sha256(payload),
                    payload_size,
                )
            )
            offset += total
            continue

        if remaining.startswith(SIGNATURE_MAGIC):
            if len(remaining) < 12:
                raise VerificationError(f"truncated signature at offset {offset:#x}")
            total = struct.unpack_from("<I", remaining, 8)[0]
            if total < 12 or total > len(remaining):
                raise VerificationError(
                    f"invalid signature size {total} at offset {offset:#x}"
                )
            member = remaining[:total]
            records.append(
                Record("signature", "m1n1-signature", offset, total, sha256(member))
            )
            offset += total
            continue

        if remaining.startswith(LOGO_MAGIC):
            total = len(LOGO_MAGIC) + LOGO_SIZE
            if total > len(remaining):
                raise VerificationError(f"truncated custom logo at offset {offset:#x}")
            member = remaining[:total]
            records.append(Record("logo", "rgba", offset, total, sha256(member)))
            offset += total
            continue

        variable = parse_variable(data, offset)
        if variable:
            name, value, next_offset = variable
            if name in variables:
                raise VerificationError(f"duplicate variable {name!r}")
            variables[name] = value
            member = data[offset:next_offset]
            records.append(
                Record("variable", name, offset, len(member), sha256(member))
            )
            offset = next_offset
            continue

        if len(remaining) >= 0x3C and remaining[0x38:0x3C] == KERNEL_MAGIC:
            raise VerificationError(
                "raw inline kernel is ambiguous and stops m1n1 payload scanning; "
                "B0 requires a gzip or XZ kernel before the DTB/initramfs"
            )
        if remaining.startswith(CPIO_MAGICS):
            raise VerificationError(
                "uncompressed inline cpio has no length; compress it or use "
                "the m1n1_initramfs wrapper"
            )

        raise VerificationError(
            f"unknown payload at offset {offset:#x}: {remaining[:8].hex()}"
        )

    if offset != len(data):
        raise VerificationError(f"parser stopped at {offset:#x} of {len(data):#x}")
    return records, variables


def verify_object(
    object_data: bytes,
    m1n1_data: bytes,
    *,
    expected: dict[str, bytes] | None = None,
    expected_bootargs: str | None = None,
    strict: bool = False,
    max_object_size: int = MAX_OBJECT_SIZE,
) -> dict:
    if len(object_data) > max_object_size:
        raise VerificationError(
            f"object size {len(object_data)} exceeds policy limit {max_object_size}"
        )
    if len(m1n1_data) % M1N1_ALIGNMENT:
        raise VerificationError(
            f"m1n1 prefix size {len(m1n1_data)} is not 16 KiB aligned"
        )
    if len(m1n1_data) <= RAW_ENTRY_POINT + 4:
        raise VerificationError("m1n1 prefix does not contain raw entry point 0x800")
    if m1n1_data[RAW_ENTRY_POINT:RAW_ENTRY_POINT + 4] == b"\0\0\0\0":
        raise VerificationError("raw entry point 0x800 contains zero padding")
    if not object_data.startswith(m1n1_data):
        raise VerificationError("object prefix is not byte-identical to supplied m1n1.bin")

    records, variables = parse_payload_stream(object_data, len(m1n1_data))
    payload_records = [r for r in records if r.role in ("kernel", "dtb", "initramfs")]
    roles = [r.role for r in payload_records]
    if roles != ["kernel", "dtb", "initramfs"]:
        raise VerificationError(
            f"B0 payload order/count is {roles!r}, expected "
            "['kernel', 'dtb', 'initramfs']"
        )
    if not records or records[-1].role != "terminator" or records[-1].size < 4:
        raise VerificationError("object lacks a deterministic four-byte zero terminator")

    expected = expected or {}
    for record in payload_records:
        wanted = expected.get(record.role)
        if wanted is None:
            if strict:
                raise VerificationError(f"no expected {record.role} artifact supplied")
            continue
        actual = object_data[record.offset:record.offset + record.size]
        if actual != wanted:
            raise VerificationError(
                f"{record.role} bytes/hash do not match supplied artifact: "
                f"{sha256(actual)} != {sha256(wanted)}"
            )

    actual_bootargs = variables.get("chosen.bootargs")
    if expected_bootargs is not None and actual_bootargs != expected_bootargs:
        raise VerificationError(
            f"chosen.bootargs mismatch: {actual_bootargs!r} != {expected_bootargs!r}"
        )
    if strict and expected_bootargs is None:
        raise VerificationError("strict mode requires --expect-bootargs")
    if strict and actual_bootargs is None:
        raise VerificationError("object has no chosen.bootargs variable")

    runtime_reserve = sum(r.runtime_reserve for r in payload_records)
    return {
        "schema": "wallace.raw-m1n1-object.v1",
        "object": {
            "size": len(object_data),
            "sha256": sha256(object_data),
            "max_size_policy": max_object_size,
        },
        "m1n1": {
            "size": len(m1n1_data),
            "sha256": sha256(m1n1_data),
            "entry_point": RAW_ENTRY_POINT,
            "alignment": M1N1_ALIGNMENT,
            "outer_magic": None,
        },
        "variables": variables,
        "records": [asdict(record) for record in records],
        "runtime_reserve": {
            "payload_bytes": runtime_reserve,
            "note": "kernel header image_size + expanded initramfs + DTB and 96 KiB growth",
        },
    }


def self_test() -> None:
    m1n1 = bytearray(M1N1_ALIGNMENT)
    m1n1[RAW_ENTRY_POINT:RAW_ENTRY_POINT + 4] = b"\x01\x02\x03\x04"

    kernel = bytearray(0x1000)
    kernel[0x38:0x3C] = KERNEL_MAGIC
    struct.pack_into("<Q", kernel, 0x10, 0x2000)
    kernel_gz = gzip.compress(bytes(kernel), mtime=0)

    dtb = bytearray(64)
    dtb[:4] = FDT_MAGIC
    struct.pack_into(">I", dtb, 4, len(dtb))

    cpio = b"070701" + b"self-test" * 32
    cpio_gz = gzip.compress(cpio, mtime=0)
    bootargs = "maxcpus=1 idle=nop"
    variable = f"chosen.bootargs={bootargs}\n".encode()
    good = bytes(m1n1) + variable + kernel_gz + bytes(dtb) + cpio_gz + b"\0" * 4
    expected = {"kernel": kernel_gz, "dtb": bytes(dtb), "initramfs": cpio_gz}

    result = verify_object(
        good,
        bytes(m1n1),
        expected=expected,
        expected_bootargs=bootargs,
        strict=True,
    )
    assert [r["role"] for r in result["records"]][-4:] == [
        "kernel", "dtb", "initramfs", "terminator"
    ]

    corrupt = bytearray(good)
    kernel_offset = next(
        r["offset"] for r in result["records"] if r["role"] == "kernel"
    )
    corrupt[kernel_offset + 8] ^= 1
    try:
        verify_object(
            bytes(corrupt),
            bytes(m1n1),
            expected=expected,
            expected_bootargs=bootargs,
            strict=True,
        )
    except VerificationError:
        pass
    else:
        raise AssertionError("corrupt compressed member was accepted")

    for bad in (
        good[:-6],
        bytes(m1n1) + variable + bytes(dtb) + kernel_gz + cpio_gz + b"\0" * 4,
        good + b"not-zero",
    ):
        try:
            verify_object(
                bad,
                bytes(m1n1),
                expected=expected,
                expected_bootargs=bootargs,
                strict=True,
            )
        except VerificationError:
            pass
        else:
            raise AssertionError("malformed object was accepted")


def parse_int(value: str) -> int:
    return int(value, 0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("object", nargs="?", type=Path)
    parser.add_argument("--m1n1", type=Path, help="exact base m1n1.bin")
    parser.add_argument("--kernel", type=Path, help="exact compressed kernel member")
    parser.add_argument("--dtb", type=Path, help="exact DTB member")
    parser.add_argument("--initramfs", type=Path, help="exact initramfs member")
    parser.add_argument("--expect-bootargs")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="require exact component files and expected embedded bootargs",
    )
    parser.add_argument(
        "--max-object-size",
        type=parse_int,
        default=MAX_OBJECT_SIZE,
        help="policy ceiling in bytes (default: 64 MiB; accepts 0x...)",
    )
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        print("self-test: PASS")
        return 0
    if args.object is None or args.m1n1 is None:
        parser.error("OBJECT and --m1n1 are required unless --self-test is used")

    component_paths = {
        "kernel": args.kernel,
        "dtb": args.dtb,
        "initramfs": args.initramfs,
    }
    if args.strict and any(path is None for path in component_paths.values()):
        parser.error("--strict requires --kernel, --dtb, and --initramfs")

    expected = {
        role: path.read_bytes()
        for role, path in component_paths.items()
        if path is not None
    }
    try:
        result = verify_object(
            args.object.read_bytes(),
            args.m1n1.read_bytes(),
            expected=expected,
            expected_bootargs=args.expect_bootargs,
            strict=args.strict,
            max_object_size=args.max_object_size,
        )
    except (OSError, VerificationError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    if args.json:
        json.dump(result, sys.stdout, indent=2, sort_keys=True)
        print()
    else:
        print(
            f"PASS object={result['object']['sha256']} "
            f"size={result['object']['size']} entry=0x{RAW_ENTRY_POINT:x}"
        )
        for record in result["records"]:
            print(
                f"{record['offset']:#010x} {record['size']:9d} "
                f"{record['role']:10s} {record['encoding']:16s} "
                f"{record['sha256']}"
            )
        print(f"runtime payload reserve: {result['runtime_reserve']['payload_bytes']} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
