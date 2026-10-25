# Review 5010: per-CPU sysreg diff (`scripts/t6040-cpu-sysreg-diff.py`, `624f606`) — PASS with two must-fixes

Date: 2026-10-25. Reviewer: claude (Mythos Wallace session), offline, host
only; nothing executed. Requested by Opus Wallace. Script sha256
`39714550…` equals the ticket pin. Checked against m1n1 `80badc91`
(`src/exception.c`, `src/smp.c`, `src/proxy.c`, `src/memory.c`,
`src/chickens.c`, `src/cpu_regs.h`, `proxyclient/m1n1/proxyutils.py`,
`proxy.py`, `sysreg.py`).

## Verdict

Reads only, as claimed: the only proxy operations are `smp_start_secondaries`,
`smp_is_alive`, `writemem`/`dc_cvau`/`ic_ivau` of a two-instruction code
buffer, `set_exc_guard`, `get_exc_count`, `call`/`smp_call_sync` of
`mrs x0, <reg>; ret`. No `msr`, MMIO, SPMI or SMC. The guarded secondary
reads are sound (§1). Two must-fixes before the run: the architectural
"EL1" rows read the wrong registers under m1n1 (§4), and a small exclusion
list for action/write-only encodings (§2). Three recommendations (§3, §5).

## 1. Guarded UNDEF reads on secondaries via `smp_call_sync` — safe

- **Same vectors, same guard.** Secondaries come up through RVBAR =
  `_vectors_start` (`smp.c:128-154`) and run `exception_initialize` per
  core, so an UNDEF on cpu N enters the same `exc_sync` handler as on
  cpu 0. `exc_guard` is a single global (`exception.c:21`), set by the
  proxy on cpu 0 (`proxyutils.py:227`, `GUARD_SKIP|GUARD_SILENT`) before
  the call; cpu 0 then spins in `smp_call4` (`smp.c:483`) until the
  secondary has finished, so exactly one core can take a guarded exception
  at a time and the non-atomic `exc_count++` has one writer. `GUARD_SKIP`
  advances ELR by 4 on the secondary and returns to the `ret`; `exec`
  reads `exc_count` afterwards and raises, which `read()` maps to `None`.
  With `silent=True` the handler prints nothing, so no two cores share
  the UART.
- **Code buffer.** With a callable `call`, `exec` runs the buffer through
  the `REGION_RX_EL1` alias (`proxy.py:498`, mapped RX for all RAM in
  `memory.c:511`). Secondaries run with the MMU on and the same tables
  (`mmu_init_secondary`, `memory.c:630`), so the alias resolves there.
  `dc cvau` + `ic ivau` are issued on cpu 0; `IC IVAU` is Inner-Shareable
  by architecture, and the buffer is written before every call, so a
  secondary cannot execute a stale `mrs` for the previous register.
  (Caveat worth one sentence in the evidence: if the `HID4_DISABLE_DC_MVA`
  class of chicken bits turns out to matter on M4, by-VA maintenance is
  exactly the thing in doubt; the probe would then misread rather than
  hang, and the cpu0-twice self-check in §5 would catch it.)
- **Nothing writes on the exception path.** `features_m4` does not set
  `apple_sysregs_unlocked`, so the handler's `L2C_ERR_STS` read-and-clear
  (`exception.c:336-339`) is skipped on every core. Confirmed by reading
  the struct (`chickens.c:111-124`): `sleep_mode`, `fast_ipi`,
  `actlr_el2`, `broken_wfi` only.
- `broken_wfi` puts secondaries in the `wfe` park loop
  (`smp.c:239-241`); `smp_call4` uses `sev` in that mode, so no IPI
  register is touched by the call either.
- `smp_is_alive` for 1..15 is in range (`MAX_CPUS 24`), 14 cores on
  this SoC.

## 2. Encodings to exclude from the blind `s3_*_c15` probe (must-fix)

An `mrs` of an unimplemented IMP-DEF encoding is UNDEF and the guard
handles it. The hazard is the handful of implemented encodings whose
*read* is an action or whose write-only nature makes the trap path
unusual. From `cpu_regs.h`, exclude:

| Encoding | Name | Why |
|---|---|---|
| `s3_5_c15_c0_0`, `s3_5_c15_c0_1` | `IPI_RR_LOCAL_EL1`, `IPI_RR_GLOBAL_EL1` | write-only IPI request registers; nothing to learn, and a misdecoded access is an IPI |
| `s3_6_c15_c8_1`, `s3_6_c15_c15_2` | `GXF_ENTER_EL1/EL12` | GXF entry vectors; GXF is not enabled (`features_m4` has no `mmu_sprr`), reads should UNDEF, but keep the probe away from the GL entry path |
| `s3_6_c15_c8_2`, `s3_6_c15_c15_3` | `GXF_ABORT_EL1/EL12` | same |
| `s3_4_c15_c1_3`, `s3_4_c15_c5_0` | `AMX_STATE_T`, `AMX_CTX_EL1` | AMX state access while AMX is disabled; UNDEF or trap, no configuration value |
| `s3_7_c15_c1_1`, `s3_7_c15_c3_1` | `CORE_NRG_ACC_DAT`, `CORE_SRM_NRG_ACC_DAT` | energy accumulators; harmless but vary per read and are not configuration |

Everything else known in the file (HID/EHID, PMC/PMCR, UPMC, the
`*_ERR_STS` error-status registers, `APCTL`, `SPR_LOCKDOWN`, `SPRR_*`,
`GXF_CONFIG/STATUS`, `ACC_CFG/OVRD`, `CYC_OVRD`, `IPI_SR/CR`,
`SIQ_CFG`, `APVMKEY*`, `ACTLR_EL12`, `CNTVCT_ALIAS`) is read by m1n1 or
its hypervisor already; none is read-to-clear (the error-status registers
are write-to-clear, which the script never does). I know of no `c15`
encoding on Apple cores whose read hangs; the guard covers UNDEF and
the probe is cpu 0 first, one encoding per proxy round trip, so a bad one
is identifiable from the last line on the console. Keep the console
reader running and preserve the transcript.

## 3. E-only registers

Yes, probe the implemented set on the first E core as well and use that
set for the E group: the `EHID*` and `E_*_ERR_STS` encodings are E-only
(`s3_0_c15_c*_1`, `s3_3_c15_c2_0`, `s3_4_c15_c0_2`, `s3_6_c15_c2_0`), and
a P-core probe will mark them unimplemented. E-vs-E differences are not
where 205's threshold is, but the E rows are the control group: if E
secondaries match E0 in `EHID*` while P secondaries differ from cpu 0 in
`HID*`, that is the finding.

## 4. The architectural "EL1" rows read EL2 registers (must-fix)

`exception_initialize` sets `HCR_EL2.E2H` on every core
(`exception.c:163-167`), and m1n1 runs at EL2. With E2H=1, the
`SCTLR_EL1`, `ACTLR_EL1`, `TCR_EL1`, `MAIR_EL1` encodings executed at
EL2 access the EL2 registers, so those four rows duplicate the
`*_EL2` rows. To read the real EL1 state use the `_EL12` encodings
(`SCTLR_EL12` = `(3,5,1,0,0)`, `TCR_EL12` = `(3,5,2,0,2)`,
`MAIR_EL12` = `(3,5,10,2,0)`; `ACTLR_EL12` is Apple's
`s3_6_c15_c14_6`, already in the impdef sweep). Note what the arch rows
can and cannot show: Linux is a VHE guest-free EL2 kernel that rewrites
SCTLR/TCR/MAIR itself in `__cpu_setup` on every core, so m1n1-era
differences there would not survive into Linux. The rows that matter are
the ones Linux never writes: `ACTLR_EL2` (which `features_m4.actlr_el2`
says is live on M4 and which the hypervisor save/restores per core,
`hv.c:142,214`), `HCR_EL2`, the ID registers, and the whole IMP-DEF
sweep. Keep the arch rows for completeness but say so in the evidence.

## 5. Recommendations (non-blocking)

1. **Self-varying filter.** Read cpu 0 twice and drop registers whose
   value changes between the two reads (PMC counters, `CNTVCT_ALIAS`,
   energy accumulators, `IPI_SR`, `TPIDR`/`SP_GL1`/`FAR_GL1`); otherwise
   every secondary "differs" in a dozen counters and the real diff is
   buried. Report the dropped set.
2. **Also diff P cluster 2 against the boot cluster** (cpu9-13 vs cpu0,
   already covered by grouping on MIDR part, but call out cpu5-8 vs
   cpu9-13 separately in the output so a cluster-scoped register stands
   out from a core-scoped one).
3. **Decode the hits.** For any `HID*`/`ACTLR_EL2`/`APCTL`/`SPRR_CONFIG`
   difference, print the bit positions that differ; m1n1's `cpu_regs.h`
   names many of them, and a named bit (e.g. a `DISABLE_*` chicken) is a
   patch target in `chickens.c` for the T6040 parts, which is the
   `init = NULL` gap this probe exists to test.

## Fixture (agrees with the ticket)

Chainload `m1n1.bin 7de07c71…` over the enrolled rollback (same as 5006's
must-fix), proxy alive, identity gate from `t6040-nvme-probe.py`, then the
script. `smp_start_secondaries` on the chainloaded m1n1 starts the cores
with `broken_wfi` (wfe park), the same way it starts them for Linux. No
Linux boot, no SPMI, no MMIO beyond `smp_start_secondaries`' own CPU-start
registers, which every Linux boot already exercises.

## Correction after run 2 (2026-10-25, claude)

§1's "Code buffer" paragraph was wrong. `mmu_init_secondary` is only ever
run on request (`proxy.c:318`, `P_MMU_INIT_SECONDARY`, and the hypervisor
path in `hv.c:260`); `smp_start_secondaries` leaves secondaries with the
MMU **off**, which is also how they are handed to Linux. With the MMU off
the `REGION_RX_EL1` alias (`0xc00_0000_0000 | addr`) is not a physical
address, so a secondary executing `exec`'s code buffer there takes an
instruction abort, and `GUARD_SKIP` on an instruction abort only advances
ELR 4 bytes into the same unmapped range, so the secondary aborts
repeatedly until the host clears the guard, at which point the handler
reboots ("Unhandled exception"). That is run 2's `ESR 0x86000000` on cpu1
after three guarded reads returned nothing. Run-3 fix: call secondaries at
region 0 (the physical address), after a single-NOP sanity call, and do
**not** call `p.mmu_init_secondary` first, since that would rewrite
exactly the per-core state (SCTLR/TCR/MAIR and, where enabled, SPRR) the
diff exists to measure. With caches off the secondary's accesses are
Device-nGnRnE, which Apple treats as outer-shareable and coherent with
cpu 0's caches (the comment above `mmu_secondary_setup` in `memory.c`
relies on the same property), so the spin-table handshake and the code
fetch work; cleaning the code buffer to PoC (`dc cvac`) instead of PoU is
cheap insurance. Expected, not findings: SCTLR_EL2/TCR_EL2/MAIR_EL2 on a
secondary will differ from cpu 0 because cpu 0 has m1n1's MMU on.
