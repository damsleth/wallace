#!/usr/bin/env python3
"""T6040 per-CPU system-register diff (ticket 205, 5010). READS ONLY.

Question: do the secondary P cores m1n1 hands to Linux differ from the
iBoot-configured boot P core in CPU configuration? 205's fault threshold is
cpu5, the second P core of the boot core's own cluster, and m1n1 has no
T6040 chicken-bit init (src/chickens.c: init NULL for every M4 core).

Run 1 wedged m1n1 during a blind sweep of every s3_*_c15 encoding, with no
record of which (cpu, register). This version (Mythos's run-2 plan):
- first pass only: the architectural ID/MMU registers plus the configuration
  registers Linux inherits (HID*/EHID*, APCTL, SPR_LOCKDOWN, ACC_*, CYC_OVRD,
  SPRR/GXF config, IPI_CR, SIQ_CFG, AMX_CTL), on cpu0, cpu1 and cpu5;
- every read is logged as "read cpuN REG" to <out>.progress BEFORE the mrs,
  and the JSON is rewritten after every read;
- secondary reads are asynchronous (smp_call) and polled from the host via
  m1n1's spin_table, so a hung secondary costs that core, not the proxy;
  secondaries run MMU-off (as Linux receives them), so their calls use the
  code buffer's physical address (run 2 took an IABT on the RX_EL1 alias),
  and a single NOP call is checked on each secondary before any read;
- side-effecting registers are never read (EXCLUDE).
- ``--ctrr`` reads only the CTRR set and ``--idle`` only the WFI power-down state (5015 step 2);
  pass them through SYSREG_ARGS of the wrapper.
Linux rewrites SCTLR/TCR/MAIR per core in __cpu_setup; rows that can carry
a 205 finding are those Linux never writes: ACTLR_EL2, HCR_EL2, ID registers
and the impdef configuration registers.

No msr, no MMIO, no SPMI. Hold the rig lease; run over the chainloaded m1n1
7de07c71 (scripts/t6040-run-sysreg-diff.sh).
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import struct
import sys
import time

sys.path.insert(0, "/Users/damsleth/code/m1n1/proxyclient")
from m1n1.setup import *  # noqa: E402,F403  (u, p, iface)
from m1n1.proxy import GUARD  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "probe", "/Users/damsleth/code/wallace/scripts/t6040-nvme-probe.py")
_probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_probe)

# m1n1 7de07c71: `nm m1n1-raw.elf` -> 00000000000dd290 b spin_table;
# struct spin_table { mpidr, flag, target, args[4], retval } = 64 bytes.
SPIN_TABLE_OFF = 0xdd290
ST_SIZE, ST_TARGET, ST_RETVAL = 64, 16, 56
SECONDARY_TIMEOUT = 3.0

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
FIRST_PASS = re.compile(
    r"IMP_APL_(E?HID\d+|APCTL_EL(1|2|12)|SPR_LOCKDOWN_EL[12]|ACC_CFG|ACC_OVRD|"
    r"CYC_OVRD|SPRR_CONFIG_EL1|GXF_CONFIG_EL1|IPI_CR_EL1|SIQ_CFG_EL1|AMX_CTL_EL[12])")


def ctrr_regs():
    """CTRR range-protection registers, named in proxyclient apple_regs.json
    (not in cpu_regs.h, so outside the 5010 first pass). 5012 showed every
    secondary denying writes around the ADT while cpu0 allows them."""
    regs = {}
    for e in json.load(open("/Users/damsleth/code/m1n1/proxyclient/m1n1/apple_regs.json")):
        if e["name"].startswith("CTRR_"):
            regs["IMP_APL_" + e["name"]] = tuple(e["enc"])
    # 5015: M4's second CTRR instance, enabled on secondaries only (Asahi m1n1
    # 442c7a2/a735ea2/00b8814, Gravity eb6cab7). Older apple_regs.json lacks it,
    # and 5012 never read it. EL1 encodings only: upstream kboot reads these
    # at EL2; the EL2/ACC/CTXR variants are left out of this pass.
    for n, enc in {"CTRR_C_LWR_EL1": (3, 0, 11, 0, 0), "CTRR_C_UPR_EL1": (3, 0, 11, 0, 1),
                   "CTRR_D_LWR_EL1": (3, 0, 11, 0, 2), "CTRR_D_UPR_EL1": (3, 0, 11, 0, 3),
                   "CTRR_C_CTL_EL1": (3, 0, 11, 1, 4), "CTRR_D_CTL_EL1": (3, 0, 11, 1, 5)}.items():
        if enc not in regs.values():
            regs["IMP_APL_" + n] = enc
    return regs


def idle_regs():
    """5015 step 2 (wallace-rex 94ea32e, c37b6f0): the per-CPU idle/power-down state. macOS idles a
    secondary with a plain WFI that keeps state; before a power-down WFI loop it arms SIQ_CFG_EL1[1:0]=3
    and clears bit 0 of s3_1_c15_c7_4 (shallow), or sets bits 0 and 63 of s3_5_c15_c6_2 (deep), and the
    per-CPU entry writes SIQ_CFG_EL1 = 0. m1n1 on M4 writes none of these, so a parked secondary may be
    left with power-down armed (the idea behind broken_wfi and idle=nop). Dict order is read order: the
    known register first, the deep-sleep arm last. Compare cpu0 (boot) with cpu1 (E) and cpu5 (P)."""
    return {
        "IMP_APL_SIQ_CFG_EL1": (3, 4, 15, 10, 4),
        "S3_4_C15_C14_6 (AGTCNTRDIR_EL12; macOS sets 3, m1n1 0)": (3, 4, 15, 14, 6),
        "S3_4_C15_C9_6 (timebase event stream; macOS ORs (index<<4)|0xf)": (3, 4, 15, 9, 6),
        "S3_1_C15_C7_4 (shallow power-down: macOS clears bit 0, never sets it)": (3, 1, 15, 7, 4),
        "S3_5_C15_C6_2 (deep power-down: macOS sets bits 0 and 63)": (3, 5, 15, 6, 2),
    }


def impdef_first_pass():
    regs = {}
    src = open("/Users/damsleth/code/m1n1/src/cpu_regs.h").read()
    for n, enc in re.findall(r"#define SYS_(\w+)\s+sys_reg\(([^)]*)\)", src):
        t = tuple(int(x, 0) for x in enc.split(","))
        if FIRST_PASS.fullmatch(n) and t not in EXCLUDE:
            regs.setdefault(n, t)
    return regs


class SecondaryHang(Exception):
    pass


PROGRESS = None
SPIN_TABLE = None


def secondary_call(cpu):
    entry = SPIN_TABLE + cpu * ST_SIZE

    def call(addr, *args):
        # Secondaries run MMU-off after smp_start_secondaries (as Linux gets
        # them): call the code buffer by physical address (region 0), and
        # clean it to PoC as well as PoU (run 2: RX_EL1 alias -> IABT).
        p.dc_cvac(u.code_buffer, u.CODE_BUFFER_SIZE)
        p.smp_call(cpu, addr, *args)
        t0 = time.time()
        while struct.unpack("<Q", iface.readmem(entry + ST_TARGET, 8))[0]:
            if time.time() - t0 > SECONDARY_TIMEOUT:
                raise SecondaryHang(cpu)
            time.sleep(0.002)
        return struct.unpack("<Q", iface.readmem(entry + ST_RETVAL, 8))[0]
    return call


def read(name, reg, cpu):
    PROGRESS.write(f"read cpu{cpu} {name} {reg}\n")
    PROGRESS.flush()
    call = None if cpu == 0 else (secondary_call(cpu), 0)
    try:
        return u.mrs(reg, silent=True, call=call)
    except SecondaryHang:
        p.set_exc_guard(GUARD.OFF)
        raise
    except Exception:  # noqa: BLE001  (UNDEF under the guard)
        return None


def main() -> int:
    global PROGRESS, SPIN_TABLE
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--cpus", default="0,1,5")
    ap.add_argument("--ctrr", action="store_true", help="read only arch ID regs + the CTRR set")
    ap.add_argument("--idle", action="store_true",
                    help="read only arch ID regs + the WFI power-down state registers (5015 step 2)")
    a = ap.parse_args()
    PROGRESS = open(a.out + ".progress", "w")
    print("== identity gate ==", flush=True)
    if not _probe.gate():
        print("GATE FAILED -> nothing read", flush=True)
        return 1
    SPIN_TABLE = u.base + SPIN_TABLE_OFF
    p.smp_start_secondaries()
    cpus = [int(x) for x in a.cpus.split(",")]
    for c in cpus[1:]:
        mp = struct.unpack("<Q", iface.readmem(SPIN_TABLE + c * ST_SIZE, 8))[0]
        print(f"cpu{c}: alive={p.smp_is_alive(c)} spin_table mpidr={mp:#x}", flush=True)
    # Sanity: one NOP on each secondary through the same path before any mrs.
    for c in cpus[1:]:
        PROGRESS.write(f"nop cpu{c}\n")
        PROGRESS.flush()
        try:
            u.exec(0xd503201f, call=(secondary_call(c), 0))
            print(f"cpu{c}: NOP call OK", flush=True)
        except SecondaryHang:
            print(f"cpu{c}: NOP call HUNG; aborting before any register read", flush=True)
            return 3
        except Exception as e:  # noqa: BLE001
            print(f"cpu{c}: NOP call raised {e}; aborting before any register read", flush=True)
            return 3
    regs = dict(ARCH)
    regs.update(ctrr_regs() if a.ctrr else idle_regs() if a.idle else impdef_first_pass())
    print(f"first pass: {len(regs)} registers on cpus {cpus}", flush=True)
    data, hung = {c: {} for c in cpus}, {}
    for c in cpus:
        for n, r in regs.items():
            try:
                v = read(n, r, c)
            except SecondaryHang:
                hung[c] = n
                print(f"SECONDARY HANG: cpu{c} on {n} {r}; skipping the rest of cpu{c}", flush=True)
                break
            data[c][n] = None if v is None else f"{v:#018x}"
            with open(a.out, "w") as f:
                json.dump({"cpus": data, "hung": hung}, f, indent=1)
        print(f"cpu{c}: {len(data[c])} registers read", flush=True)
    print("\n== diff vs cpu0 (boot P) ==", flush=True)
    for c in cpus[1:]:
        for n in regs:
            if n == "MPIDR_EL1" or n not in data[c]:
                continue
            if data[c][n] != data[0].get(n):
                print(f"  cpu{c} {n}: {data[c][n]}  (cpu0: {data[0].get(n)})", flush=True)
    print(f"\nSYSREG-DIFF DONE hung={hung}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
