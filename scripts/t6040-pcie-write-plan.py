#!/usr/bin/env python3
"""Expand the J614s ADT into the exact m1n1 T6040 PCIe write plan.

This is a host-only review tool. It does not open a proxy connection and does
not perform MMIO. Feed it the committed j614s.adt from the Linux tree; stdout is
a deterministic TSV containing one row per write in pcie_init_controller().
"""

from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import struct
import sys
from dataclasses import dataclass


DEFAULT_M1N1 = pathlib.Path("/Users/damsleth/Code/m1n1")


@dataclass(frozen=True)
class Write:
    phase: str
    source: str
    address: int
    size: int
    operation: str
    mask: int
    value: int


def attr_name(prop: str) -> str:
    return prop.replace("-", "_")


def parse_local_raw(raw: bytes):
    if len(raw) % 24:
        raise ValueError(f"local tunable length {len(raw)} is not a multiple of 24")
    return struct.iter_unpack("<IIQQ", raw)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("adt", nargs="?", type=pathlib.Path,
                        help="raw j614s.adt; stdin when omitted")
    parser.add_argument("--m1n1", type=pathlib.Path, default=DEFAULT_M1N1,
                        help="m1n1 checkout containing proxyclient/m1n1/adt.py")
    args = parser.parse_args()

    sys.path.insert(0, str(args.m1n1 / "proxyclient"))
    try:
        from m1n1 import adt  # pylint: disable=import-outside-toplevel
    except ModuleNotFoundError as exc:
        venv_python = args.m1n1 / "venv/bin/python"
        if (exc.name == "construct" and venv_python.exists()
                and pathlib.Path(sys.executable) != venv_python):
            os.execv(venv_python, [str(venv_python), *sys.argv])
        raise

    data = args.adt.read_bytes() if args.adt else sys.stdin.buffer.read()
    tree = adt.load_adt(data)
    node = tree["/arm-io/apcie0"]
    if "apcie,t6040" not in node.compatible:
        raise SystemExit(f"unexpected apcie0 compatible: {node.compatible!r}")
    if node.getprop("#ports") != 4:
        raise SystemExit(f"unexpected apcie0 port count: {node.getprop('#ports')!r}")

    regs = [node.get_reg(i) for i in range(len(node.reg))]
    expected = {
        0: (0x1CB0000000, 0x10000000),
        1: (0x414000000, 0x4000),
        2: (0x417000000, 0x40000),
        3: (0x417040000, 0x28000),
        4: (0x416000000, 0x1000000),
        5: (0x415046200, 0x4000),
        6: (0x415044000, 0x4000),
    }
    for index, value in expected.items():
        if regs[index] != value:
            raise SystemExit(f"apcie0 reg[{index}] changed: {regs[index]!r}")
    if len(regs) != 35:
        raise SystemExit(f"unexpected apcie0 reg count: {len(regs)}")

    writes: list[Write] = []

    def add(phase: str, source: str, address: int, size: int,
            operation: str, mask: int, value: int) -> None:
        width_mask = (1 << (size * 8)) - 1
        if mask & ~width_mask or value & ~width_mask:
            raise ValueError(f"{source}: operand exceeds {size}-byte width")
        writes.append(Write(phase, source, address, size, operation, mask, value))

    def write32(phase: str, source: str, address: int, value: int) -> None:
        add(phase, source, address, 4, "WRITE", 0xFFFFFFFF, value)

    def set32(phase: str, source: str, address: int, bits: int) -> None:
        add(phase, source, address, 4, "SET", bits, bits)

    def clear32(phase: str, source: str, address: int, bits: int) -> None:
        add(phase, source, address, 4, "CLEAR", bits, 0)

    def rmw(phase: str, source: str, address: int, size: int,
            mask: int, value: int) -> None:
        add(phase, source, address, size, "RMW", mask, value)

    def local_parsed(phase: str, source: str, base: int, tunables) -> None:
        for item in tunables:
            rmw(phase, source, base + int(item.offset), int(item.size),
                int(item.mask), int(item.value))

    def local_raw(phase: str, source: str, base: int, raw: bytes) -> None:
        for offset, size, mask, value in parse_local_raw(raw):
            rmw(phase, source, base + offset, size, mask, value)

    # pmgr_adt_power_enable(): preserve m1n1's recursive order and duplicates.
    # PMGR_FLAG_VIRTUAL is 0x10, represented as "critical" by the Python ADT
    # parser. Virtual nodes recurse to parents but do not receive a write.
    pmgr = tree["/arm-io/pmgr"]
    by_id = {tree.pmgr_dev_get_id(dev): dev for dev in pmgr.devices}
    pmgr_mask = 0x1000030F
    pmgr_active = 0x0000000F

    def enable_pmgr(device_id: int, die: int) -> None:
        if not device_id:
            return
        dev = by_id[device_id]
        for parent in tree.pmgr_dev_get_parents(dev):
            if parent:
                enable_pmgr(parent, die)
        if not dev.flags.critical:
            address = tree.pmgr_dev_get_addr(dev) + die * 0x2000000000
            rmw("pmgr", f"clock-gate:{device_id}:{dev.name}", address, 4,
                pmgr_mask, pmgr_active)

    for encoded in node.clock_gates:
        enable_pmgr(int(encoded) & 0xFFFF, (int(encoded) >> 28) & 0xF)

    axi = regs[4][0]
    rc = regs[1][0]
    phy_reg = regs[2][0]
    phy = phy_reg + 0x8000       # APCIE_T8122 compatibility adjustment
    phy_common = phy_reg + 0x4000
    phy_ip = regs[3][0]

    local_parsed("controller", "apcie-axi2af-tunables", axi,
                 getattr(node, attr_name("apcie-axi2af-tunables")))
    write32("controller", "pcie.c:rc+0x4", rc + 0x4, 0)
    if hasattr(node, attr_name("apcie-common-tunables")):
        local_parsed("controller", "apcie-common-tunables", rc,
                     getattr(node, attr_name("apcie-common-tunables")))
    local_parsed("controller", "apcie-cio3pllcore-tunables", regs[5][0],
                 getattr(node, attr_name("apcie-cio3pllcore-tunables")))
    local_parsed("controller", "apcie-pcieclkgen-tunables", regs[6][0],
                 getattr(node, attr_name("apcie-pcieclkgen-tunables")))
    local_parsed("controller", "apcie-phy-tunables", phy_reg,
                 getattr(node, attr_name("apcie-phy-tunables")))

    set32("phy", "CLK0REQ", phy, 0x1)
    set32("phy", "CLK1REQ", phy, 0x2)
    clear32("phy", "RESET", phy, 0x80)
    set32("phy", "T8122 pre-tunable control", phy + 0x4, 0x1)
    local_parsed("phy", "apcie-phy-ip-pll-tunables", phy_ip,
                 getattr(node, attr_name("apcie-phy-ip-pll-tunables")))
    local_parsed("phy", "apcie-phy-ip-auspma-tunables", phy_ip,
                 getattr(node, attr_name("apcie-phy-ip-auspma-tunables")))
    set32("phy", "T8122 post-tunable control", phy + 0x4, 0x10)
    rmw("phy", "PHYCMN clock mode", phy_common, 4, 0x3, 0x1)
    set32("phy", "T8122 PHY control", phy, 0x200)
    write32("phy", "RC init", rc + 0x54, 0x140)
    write32("phy", "RC init", rc + 0x50, 0x1)

    port_reg_count = 7
    config = regs[0][0]
    for port, bridge_name in enumerate(("pci-bridge0", "pci-bridge1")):
        bridge = node[bridge_name]
        index = 7 + port * port_reg_count
        port_base = regs[index][0]
        port_phy = regs[index + 2][0]
        intr2axi = regs[index + 4][0]
        phase = f"port{port}"

        clear32(phase, "T6031 AXI control", axi + 0x600, 0x10000)
        for offset, value in (
            (0x88, 0x110), (0x100, 0xFFFFFFFF), (0x148, 0xFFFFFFFF),
            (0x210, 0xFFFFFFFF), (0x80, 0), (0x84, 0),
            (0x104, 0xFFFFFFF0), (0x124, 0x100), (0x16C, 0),
            (0x13C, 0x10), (0x800, 0x100100), (0x808, 0x1000FF),
            (0x82C, 0),
        ):
            write32(phase, "T8122 port init", port_base + offset, value)
        for item in range(16):
            write32(phase, "RID2SID clear", port_base + 0x3000 + 4 * item, 0)
        for item in range(512):
            write32(phase, "MSIMAP clear", port_base + 0x3800 + 4 * item, 0)
        for offset, value in (
            (0x130, 0x03000000), (0x140, 0x10), (0x144, 0x253770),
            (0x21C, 0), (0x834, 0), (0x83C, 0),
        ):
            write32(phase, "T8122 port init", port_base + offset, value)

        local_raw(phase, f"{bridge_name}:apcie-config-tunables", port_base,
                  bridge._properties["apcie-config-tunables"])
        set32(phase, "APPCLK enable", port_base + 0x800, 0x1)
        clear32(phase, "port PHY clear clock requests", port_phy, 0x3)
        set32(phase, "port PHY CLK0REQ", port_phy, 0x1)
        set32(phase, "port PHY CLK1REQ", port_phy, 0x2)
        clear32(phase, "T8122 port PHY control", port_phy, 0x10)
        set32(phase, "port PHY control", port_phy, 0x200)
        set32(phase, "port PHY control", port_phy, 0x400)
        set32(phase, "PERST# deassert", port_base + 0x82C, 0x1)

        set32(phase, "DBI read-only write enable", config + 0x8BC, 0x1)
        for prop in (
            "pcie-rc-tunables",
            "pcie-rc-gen3-shadow-tunables",
            "pcie-rc-gen4-shadow-tunables",
        ):
            local_raw(phase, f"{bridge_name}:{prop}", config,
                      bridge._properties[prop])

        speed = int(bridge.maximum_link_speed)
        if speed == 1:
            first_child = next(iter(bridge), None)
            if first_child is not None:
                override = getattr(first_child, "target_link_speed", None)
                if not override:
                    override = getattr(first_child, "expected_link_speed", None)
                if override and int(override) > 0:
                    speed = int(override)
        if speed <= 0:
            raise SystemExit(f"invalid link speed for {bridge_name}: {speed}")
        rmw(phase, "PCIe LNKCAP speed", config + 0x7C, 4, 0xF, speed)
        rmw(phase, "PCIe LNKCAP2 speeds", config + 0x9C, 4, 0x7E,
            ((1 << speed) - 1) << 1)
        rmw(phase, "PCIe LNKCTL2 target speed", config + 0xA0, 2, 0xF, speed)
        set32(phase, "DesignWare speed change", config + 0x80C, 0x20000)
        rmw(phase, "DesignWare 1-lane mode", config + 0x710, 4,
            0x3F0000, 0x10000)
        rmw(phase, "DesignWare link width 1", config + 0x80C, 4,
            0x1F00, 0x100)
        rmw(phase, "PCIe LNKCAP width 1", config + 0x7C, 4, 0x3F0, 0x10)
        clear32(phase, "DBI read-only write disable", config + 0x8BC, 0x1)
        write32(phase, "T6031 post-link control", port_base + 0x4020, 0x3)
        write32(phase, "Intr2AXI enable", intr2axi + 0x80, 0x1)
        clear32(phase, "RC post-link control", rc + 0x3C, 0x1)
        for item in range(32):
            write32(phase, "MSIMAP vector", port_base + 0x3800 + 4 * item,
                    0x80000000 | item)

        config += 1 << 15

    print(f"# source_sha256\t{hashlib.sha256(data).hexdigest()}")
    print("# scope\tm1n1 pcie_init_controller(APCIE, /arm-io/apcie0), "
          "T6040 path at eb23c423")
    print("# semantics\tWRITE replaces the full value; RMW is (old & ~mask) | value; "
          "SET is old | mask; CLEAR is old & ~mask")
    print("sequence\tphase\tsource\taddress\tsize\toperation\tmask\tvalue")
    for sequence, item in enumerate(writes, 1):
        digits = item.size * 2
        print(f"{sequence}\t{item.phase}\t{item.source}\t0x{item.address:011x}\t"
              f"{item.size}\t{item.operation}\t0x{item.mask:0{digits}x}\t"
              f"0x{item.value:0{digits}x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
