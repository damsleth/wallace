#!/usr/bin/env python3
"""Map T6040 ATC PHY tunables to ADT register banks from the paired kext.

This is a host-only static-analysis tool. It reads an already extracted
AppleT6040TypeCPhy Mach-O and an already captured ADT. It never opens a proxy,
device node, MMIO mapping, SPMI controller, or target connection.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import struct
import sys


DEFAULT_M1N1 = pathlib.Path("/Users/damsleth/Code/m1n1")
EXPECTED_KEXT_SHA256 = (
    "d0a766201c15bb01b8eeaf6617c91707562ae0c50511ebfccbd9d918acd499f3"
)
EXPECTED_COMPATIBLE = "atc-phy,t6040"

# Exact 25F84 AppleT6040TypeCPhy extraction:
#   symbol __ZN18AppleT6040TypeCPhy11_sRegistersE
#   VA 0xfffffe000c778920, file offset 0x500c8
REGISTER_TABLE_OFFSET = 0x500C8
REGISTER_COUNT = 44
PROFILE_COUNT = 8
REGISTER_ENTRY_SIZE = 16


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def signed_27(value: int) -> int:
    value &= 0x7FFFFFF
    return value - 0x8000000 if value & 0x4000000 else value


def load_register_profiles(kext: bytes) -> list[list[tuple[int, int]]]:
    table_size = REGISTER_COUNT * PROFILE_COUNT * REGISTER_ENTRY_SIZE
    end = REGISTER_TABLE_OFFSET + table_size
    if end > len(kext):
        raise ValueError("truncated AppleT6040TypeCPhy _sRegisters table")

    profiles = [[] for _ in range(PROFILE_COUNT)]
    for bank in range(REGISTER_COUNT):
        for profile in range(PROFILE_COUNT):
            offset = REGISTER_TABLE_OFFSET + (
                bank * PROFILE_COUNT + profile
            ) * REGISTER_ENTRY_SIZE
            profiles[profile].append(struct.unpack_from("<QQ", kext, offset))
    return profiles


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kext", type=pathlib.Path)
    parser.add_argument("adt", type=pathlib.Path)
    parser.add_argument("--node", default="/arm-io/atc-phy2")
    parser.add_argument("--m1n1", type=pathlib.Path, default=DEFAULT_M1N1)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    sys.path.insert(0, str(args.m1n1 / "proxyclient"))
    try:
        from m1n1 import adt  # pylint: disable=import-outside-toplevel
    except ModuleNotFoundError as exc:
        venv_python = args.m1n1 / "venv/bin/python"
        if (
            exc.name == "construct"
            and venv_python.exists()
            and pathlib.Path(sys.executable) != venv_python
        ):
            os.execv(venv_python, [str(venv_python), *sys.argv])
        raise

    kext = args.kext.read_bytes()
    kext_digest = sha256(kext)
    if kext_digest != EXPECTED_KEXT_SHA256:
        raise SystemExit(
            "unexpected AppleT6040TypeCPhy kext SHA-256: "
            f"{kext_digest} (expected {EXPECTED_KEXT_SHA256})"
        )

    tree = adt.load_adt(args.adt.read_bytes())
    node = tree[args.node]
    compatible = tuple(node.compatible)
    if EXPECTED_COMPATIBLE not in compatible:
        raise SystemExit(f"{args.node}: unexpected compatible {compatible!r}")

    registers = [node.get_reg(i) for i in range(len(node.reg))]
    if len(registers) != REGISTER_COUNT:
        raise SystemExit(
            f"{args.node}: {len(registers)} register ranges, "
            f"expected {REGISTER_COUNT}"
        )

    profiles = load_register_profiles(kext)
    matches = [
        profile_index
        for profile_index, profile in enumerate(profiles)
        if profile == registers
    ]
    if len(matches) != 1:
        raise SystemExit(
            f"{args.node}: expected one exact kext profile match, found {matches}"
        )
    profile_index = matches[0]

    banks = [
        {
            "bank": index,
            "adt_reg": index,
            "base": base,
            "size": size,
        }
        for index, (base, size) in enumerate(registers)
    ]

    tunables = []
    for name in sorted(node._properties):
        if not name.startswith("tunable_"):
            continue
        raw = node.getprop(name)
        if raw is None:
            continue
        if not isinstance(raw, bytes):
            # Legacy tunable-host/device are parsed containers with a
            # different format. The T6040 banked records are raw <III>.
            continue
        if len(raw) % 12:
            raise SystemExit(f"{name}: length {len(raw)} is not a multiple of 12")
        for entry, (encoded, mask, value) in enumerate(
            struct.iter_unpack("<III", raw)
        ):
            bank = encoded >> 27
            offset = signed_27(encoded)
            valid_bank = bank < 31
            base, size = registers[bank] if valid_bank else (0, 0)
            in_range = valid_bank and offset >= 0 and offset + 4 <= size
            tunables.append(
                {
                    "property": name,
                    "entry": entry,
                    "bank": bank,
                    "adt_reg": bank,
                    "offset": offset,
                    "address": base + offset if in_range else None,
                    "mask": mask,
                    "value": value,
                    "in_range": in_range,
                }
            )

    result = {
        "kext_sha256": kext_digest,
        "node": args.node,
        "compatible": compatible,
        "matched_profile": profile_index,
        "banks": banks,
        "tunables": tunables,
    }
    if args.json:
        json.dump(result, sys.stdout, indent=2)
        print()
        return 0

    print(f"KEXT_SHA256\t{kext_digest}")
    print(f"NODE\t{args.node}")
    print(f"MATCHED_PROFILE\t{profile_index}")
    print("BANK\tADT_REG\tBASE\tSIZE")
    for item in banks:
        print(
            f"{item['bank']}\t{item['adt_reg']}\t"
            f"{item['base']:#x}\t{item['size']:#x}"
        )
    print(
        "PROPERTY\tENTRY\tBANK\tADT_REG\tOFFSET\tADDRESS\tMASK\tVALUE\tSTATUS"
    )
    for item in tunables:
        address = f"{item['address']:#x}" if item["address"] is not None else "-"
        print(
            f"{item['property']}\t{item['entry']}\t{item['bank']}\t"
            f"{item['adt_reg']}\t{item['offset']:#x}\t"
            f"{address}\t"
            f"{item['mask']:#010x}\t{item['value']:#010x}\t"
            f"{'mapped' if item['in_range'] else 'driver-skips'}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
