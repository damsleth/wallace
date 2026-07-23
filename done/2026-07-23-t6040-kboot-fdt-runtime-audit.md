# T6040 m1n1 kboot FDT / reserved-memory handoff audit — ticket 038 (2026-07-23)

Static audit of `~/Code/m1n1` `src/kboot.c` (+ `kboot_gpu.c`, `kboot_atc.c`,
`kboot_t6020_compat.c`, `isp.c`) vs the Linux `wallace/t6040-bringup`
`t6040*.dts*`. Read-only. Evidence matrix with file:line; no code changed.

## Headline

The T6040 bring-up **kernel DT is minimal** — `t6040.dtsi` is self-contained (it
does **not** include `t602x-die0/dieX.dtsi`) and defines only CPUs, AIC, pmgr,
wdt, ANS/NVMe, MTP-HID, USB-DRD, serial. It has **no dcp/dcpext/disp0/isp/sep/
smc/pmp nodes**, and `t6040-j614s.dts` declares only the `serial0` alias. Every
m1n1 coprocessor fixup keys off an FDT alias/node and **returns 0 (silent skip)
when the node is absent** — so m1n1 currently emits almost none of the
ISP/SEP/SMC/PMP/dcpext carveouts for T6040, because the target nodes don't exist
yet, not because m1n1 refuses.

## The one real m1n1 code defect: ISP chip_id gating (`isp.c`)

`isp_init()` (called `kboot.c:2775`, return value ignored) fails for T6040
(`chip_id==0x6040`, `soc.h:33`) at two points:
1. `pmgr_off` switch `isp.c:82-99` — cases cover T6020–T6022 and T6031–T6034;
   `0x6040` hits `default → "isp: Unsupported SoC"; return -1`.
2. `ver_rev` switch `isp.c:113-166` — only `ISP_VER_T6020`/`ISP_VER_T6031`
   defined; no T6040 → `default → return -1`.
Consequence: `dt_set_isp_fwdata` (`kboot.c:2234`) takes the "enabled but not
initialized → disable" path and emits no `isp-heap` carveout. (`isp_iova_base()`
`isp.c:42` is the one ISP function that *does* handle 0x6040.) **Fix needs a
T6040 ISP `pmgr_off` + an `ISP_VER_T6040` revision constant.**

## Evidence matrix (handled vs inert for T6040)

| Fixup | State | Anchor |
|---|---|---|
| /chosen, initrd, fw-versions, RNG seed, MAC | ✅ generic | `dt_set_chosen` 257, `dt_set_rng_seed_sep` 109/130 |
| framebuffer fill | ✅ generic (not reserved-mem, by design) | `dt_set_fb` 181-255 |
| CPU spin-table / release-addr | ✅ generic | `dt_set_cpus` 542-621 |
| AIC match (`apple,t8122-aic3` fallback) | ✅ (DT carries it) | `t6040.dtsi:303` |
| /memory + reserved-memory→RAM carve | ✅ generic | `dt_set_memory` 351-443 |
| top-of-RAM logbuf guard | ✅ T6040-specific (deliberate SError workaround) | `kboot.c:2745-2751` |
| Display/DCP carveout (region-id 49/50/57/94/95/157) | ⚠️ code path exists, **inert** (no `dcp` alias) | `dt_set_display` 1936, T6040 branch 1984-2000, skip 1685 |
| dcpext firmware / data regions | ⚠️ inert; **data regions never carved on t602x/T6040 path** | 2014-2019; latent gap comment 1993-1994 |
| SEP firmware carveout | ⚠️ generic, inert (no `sep` alias) | `dt_set_sep` 2086-2107 |
| PMP | ⚠️ generic, inert (no `pmp` node) | `dt_set_pmp` 2043-2080 |
| SMC | ⚠️ not fixed up; compat shim **excludes T6040** | `dt_fixup_t6020_compat` gate 2855-2858 |
| SIO firmware | ⚠️ inert (no `sio` node) | `dt_setup_sio` 2201 |
| ISP heap + node enable | ❌ **chip_id gap (defect above)** | `isp.c:82-99, 113-166` |
| GPU | ❌ no T6040 case (same class as ISP) | `kboot_gpu.c:88-90` |

## Prioritized gaps blocking a clean T6040 handoff

1. **ISP chip_id gap** — the one active m1n1 defect; needs T6040 `pmgr_off` +
   `ISP_VER_T6040`. Everything else ISP is ready.
2. **Coprocessor carveouts are inert because the kernel DT lacks the nodes** —
   dcp/dcpext/disp0/isp/sep/smc/pmp + aliases must be added to the T6040 DT
   before m1n1's (generic, ready) fixups emit anything. This is the gating item
   for SEP/SMC/PMP/dcpext handoff, and it dovetails with the SMC DT work
   (ticket 061) and the display/DCP enablement (Stage F, upstream).
3. **dcpext data regions never carved on the t602x/T6040 path** (`1993-1994`) —
   latent; surfaces once dcpext nodes exist; confirm M4 DCP fw needs them.
4. **T6040 excluded from `dt_fixup_t6020_compat`** — low risk, but future T6040
   coprocessor nodes relying on a generic `apple,*` fallback get no compat
   rewrite; no T6040 equivalent of `kboot_t6020_compat.c` exists.

## Conclusion

Not boot-blocking for the current B0/RAM-distro path (which uses none of these
coprocessors). It becomes relevant as Stage-D/G coprocessors are enabled: the ISP
chip_id fix is a concrete small m1n1 patch (fold into ticket 046's series when an
ISP node exists); the rest is gated on the kernel DT gaining the coprocessor
nodes (SMC first, ticket 061). Ticket 038 done.
