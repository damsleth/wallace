#!/usr/bin/env python3
"""T6040 per-CPU system-register diff (ticket 205, 5010). READS ONLY.

Question: do the secondary P cores m1n1 hands to Linux differ from the
iBoot-configured boot P core in CPU configuration? 205's fault threshold is
cpu5, the second P core of the boot core's own cluster, and m1n1 has no
T6040 chicken-bit init (src/chickens.c: init NULL for every M4 core).

For every online CPU: MPIDR/MIDR, the architectural MMU and ID registers,
and every implementation-defined s3_{op1}_c15_c{m}_{op2} register, each read
with mrs under the m1n1 exception guard (an UNDEF is recorded, not fatal).
Registers are probed on the boot CPU first; secondaries read only those
that exist there or are architectural. Then the diff: P secondaries vs the
boot P core, E cores vs E core 0.

No msr, no MMIO, no SPMI. Hold the rig lease; run on the chainloaded
NVMe-era m1n1 (7de07c71), which is what starts Linux's secondaries.
    M1N1DEVICE=/tmp/m1n1 venv/bin/python scripts/t6040-cpu-sysreg-diff.py --out FILE.json
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys

sys.path.insert(0, "/Users/damsleth/Code/m1n1/proxyclient")
from m1n1.setup import *  # noqa: E402,F403  (u, p, iface)

_spec = importlib.util.spec_from_file_location(
    "probe", "/Users/damsleth/Code/wallace/scripts/t6040-nvme-probe.py")
_probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_probe)

ARCH = {
    "MIDR_EL1": (3, 0, 0, 0, 0), "MPIDR_EL1": (3, 0, 0, 0, 5),
    "REVIDR_EL1": (3, 0, 0, 0, 6),
    "ID_AA64PFR0_EL1": (3, 0, 0, 4, 0), "ID_AA64PFR1_EL1": (3, 0, 0, 4, 1),
    "ID_AA64MMFR0_EL1": (3, 0, 0, 7, 0), "ID_AA64MMFR1_EL1": (3, 0, 0, 7, 1),
    "ID_AA64MMFR2_EL1": (3, 0, 0, 7, 2), "ID_AA64ISAR0_EL1": (3, 0, 0, 6, 0),
    "ID_AA64ISAR1_EL1": (3, 0, 0, 6, 1), "ID_AA64DFR0_EL1": (3, 0, 0, 5, 0),
    "SCTLR_EL1": (3, 0, 1, 0, 0), "ACTLR_EL1": (3, 0, 1, 0, 1),
    "TCR_EL1": (3, 0, 2, 0, 2), "MAIR_EL1": (3, 0, 10, 2, 0),
    "SCTLR_EL2": (3, 4, 1, 0, 0), "ACTLR_EL2": (3, 4, 1, 0, 1),
    "HCR_EL2": (3, 4, 1, 1, 0), "TCR_EL2": (3, 4, 2, 0, 2),
    "MAIR_EL2": (3, 4, 10, 2, 0), "CNTHCTL_EL2": (3, 4, 14, 1, 0),
}
IMPDEF = {f"s3_{o1}_c15_c{m}_{o2}": (3, o1, 15, m, o2)
          for o1 in range(8) for m in range(16) for o2 in range(8)}


def read(reg, cpu):
    call = None if cpu == 0 else (lambda addr, *a: p.smp_call_sync(cpu, addr, *a))
    try:
        return u.mrs(reg, silent=True, call=call)
    except Exception:  # noqa: BLE001  (UNDEF under the guard)
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--cpus", default="all", help="comma list or 'all'")
    a = ap.parse_args()
    print("== identity gate ==")
    if not _probe.gate():
        print("GATE FAILED -> nothing read")
        return 1
    p.smp_start_secondaries()
    alive = [c for c in range(1, 16) if p.smp_is_alive(c)]
    cpus = [0] + alive if a.cpus == "all" else [int(x) for x in a.cpus.split(",")]
    print(f"online: {cpus}")
    names = dict(ARCH)
    impl0 = {n: r for n, r in IMPDEF.items() if read(r, 0) is not None}
    print(f"boot CPU implements {len(impl0)} of {len(IMPDEF)} s3_*_c15 registers")
    data = {}
    for cpu in cpus:
        regs = {}
        for n, r in list(ARCH.items()) + list(impl0.items()):
            v = read(r, cpu)
            regs[n] = None if v is None else f"{v:#018x}"
        data[cpu] = regs
        print(f"cpu{cpu}: MPIDR={regs.get('MPIDR_EL1')} MIDR={regs.get('MIDR_EL1')}")
    with open(a.out, "w") as f:
        json.dump({"cpus": data}, f, indent=1)

    def kind(c):
        return int(data[c]["MIDR_EL1"] or "0", 16) >> 4 & 0xfff
    boot_kind = kind(0)
    groups = {}
    for c in cpus:
        groups.setdefault(kind(c), []).append(c)
    for k, members in groups.items():
        ref = members[0]
        label = "P(boot type)" if k == boot_kind else f"part {k:#x}"
        print(f"\n== {label}: reference cpu{ref}, members {members}")
        for c in members[1:]:
            diffs = [n for n in data[ref] if data[ref][n] != data[c][n]
                     and n not in ("MPIDR_EL1",)]
            for n in diffs:
                print(f"  cpu{c} {n}: {data[c][n]}  (cpu{ref}: {data[ref][n]})")
            if not diffs:
                print(f"  cpu{c}: identical to cpu{ref}")
    print("\nSYSREG-DIFF DONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
