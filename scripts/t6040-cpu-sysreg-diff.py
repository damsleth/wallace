#!/usr/bin/env python3
"""T6040 per-CPU system-register diff (ticket 205, 5010). READS ONLY.

Question: do the secondary P cores m1n1 hands to Linux differ from the
iBoot-configured boot P core in CPU configuration? 205's fault threshold is
cpu5, the second P core of the boot core's own cluster, and m1n1 has no
T6040 chicken-bit init (src/chickens.c: init NULL for every M4 core).

For every online CPU: MPIDR/MIDR, the architectural MMU and ID registers,
and every implementation-defined s3_{op1}_c15_c{m}_{op2} register, each read
with mrs under the m1n1 exception guard (an UNDEF is recorded, not fatal).
Implemented impdef registers are probed on the boot CPU (P) and on the first
E core; registers that change between two reads on cpu0 are dropped as
volatile; side-effecting registers are never read (EXCLUDE). Then the diff,
labelled by cluster and by cpu_regs.h name: P secondaries vs the boot P core,
E cores vs the first E core. Linux rewrites SCTLR/TCR/MAIR per core in
__cpu_setup, so the rows that can carry a 205 finding are those Linux never
writes: ACTLR_EL2, HCR_EL2, the ID registers and the impdef sweep.

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
    # m1n1 runs at EL2 with HCR_EL2.E2H=1: EL1 registers via _EL12.
    "SCTLR_EL12": (3, 5, 1, 0, 0), "TCR_EL12": (3, 5, 2, 0, 2),
    "MAIR_EL12": (3, 5, 10, 2, 0),
    "SCTLR_EL2": (3, 4, 1, 0, 0), "ACTLR_EL2": (3, 4, 1, 0, 1),
    "HCR_EL2": (3, 4, 1, 1, 0), "TCR_EL2": (3, 4, 2, 0, 2),
    "MAIR_EL2": (3, 4, 10, 2, 0), "CNTHCTL_EL2": (3, 4, 14, 1, 0),
}
# Never read (Mythos 5010 review): write-only IPI requests, GXF enter/abort,
# AMX state, and energy accumulators.
EXCLUDE = {(3, 5, 15, 0, 0), (3, 5, 15, 0, 1), (3, 6, 15, 8, 1), (3, 6, 15, 8, 2),
           (3, 6, 15, 15, 2), (3, 6, 15, 15, 3), (3, 4, 15, 1, 3), (3, 4, 15, 5, 0),
           (3, 7, 15, 1, 1), (3, 7, 15, 3, 1)}
IMPDEF = {f"s3_{o1}_c15_c{m}_{o2}": (3, o1, 15, m, o2)
          for o1 in range(8) for m in range(16) for o2 in range(8)
          if (3, o1, 15, m, o2) not in EXCLUDE}


def regnames():
    """Name impdef encodings from m1n1's cpu_regs.h."""
    import re
    names = {}
    src = open("/Users/damsleth/Code/m1n1/src/cpu_regs.h").read()
    for n, enc in re.findall(r"#define SYS_(\w+)\s+sys_reg\(([^)]*)\)", src):
        t = tuple(int(x, 0) for x in enc.split(","))
        names.setdefault(f"s3_{t[1]}_c{t[2]}_c{t[3]}_{t[4]}", n)
    return names


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
    def part(cpu):
        v = read(ARCH["MIDR_EL1"], cpu)
        return None if v is None else v >> 4 & 0xfff
    # Probe the implemented impdef set on cpu0 (P) and on the first core of
    # each other part (E): EHID* and E_*_ERR_STS exist only on E cores.
    probe = {}
    for c in cpus:
        k = part(c)
        if k not in probe:
            probe[k] = {n: r for n, r in IMPDEF.items() if read(r, c) is not None}
            print(f"part {k:#x} (probed on cpu{c}) implements {len(probe[k])} s3_*_c15 registers")
    # Drop registers that change between two reads on cpu0 (counters etc.).
    k0 = part(0)
    first = {n: read(r, 0) for n, r in probe[k0].items()}
    volatile = sorted(n for n, r in probe[k0].items() if read(r, 0) != first[n])
    print(f"volatile on cpu0 (excluded from the diff): {volatile}")
    data = {}
    for cpu in cpus:
        regs = {}
        for n, r in list(ARCH.items()) + list(probe[part(cpu)].items()):
            v = read(r, cpu)
            regs[n] = None if v is None else f"{v:#018x}"
        data[cpu] = regs
        print(f"cpu{cpu}: MPIDR={regs.get('MPIDR_EL1')} MIDR={regs.get('MIDR_EL1')}")
    names = regnames()
    with open(a.out, "w") as f:
        json.dump({"cpus": data, "volatile": volatile, "names": names}, f, indent=1)

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
            mp = int(data[c]["MPIDR_EL1"] or "0", 16)
            diffs = [n for n in data[ref] if data[ref][n] != data[c].get(n)
                     and n not in ("MPIDR_EL1",) and n not in volatile]
            for n in diffs:
                print(f"  cpu{c} [cluster {mp >> 8 & 0xff}/{mp >> 16 & 0xff}] "
                      f"{n} {names.get(n, '')}: {data[c].get(n)}  (cpu{ref}: {data[ref][n]})")
            if not diffs:
                print(f"  cpu{c}: identical to cpu{ref}")
    print("\nSYSREG-DIFF DONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
