# m1n1 CTRR_C secondary-only reservation (ticket 5015)

These are verbatim `git format-patch` exports from AsahiLinux/m1n1 `main`, with
the original authors kept:

| Patch | Upstream | Author |
|---|---|---|
| 0001 | `a735ea2` kboot: add reserved CTRR_M4 region | Yureka |
| 0002 | `442c7a2` cpu_regs: Add CTRR/CTXR sysregs used by SPTM | Sven Peter |
| 0003 | `00b8814` kboot: Fix M4* boot under hypervisor | Janne Grunau |
| 0004 | local, not upstream | CJ Damsleth (AI-written, see below) |
| 0005 | local, not upstream | CJ Damsleth (AI-written): reserve the SEP/coprocessor chain |
| 0006 | local, not upstream | CJ Damsleth (AI-written): PMGR clusters-table start bit, optional |
| 0007 | local, not upstream | CJ Damsleth (AI-written): length-checked memory-map reads, required hardening for 0004/0005 |

Apply them in order to the m1n1 fork (`git am`). After 0003, kboot reads
`CTRR_C_{LWR,UPR}_EL1` (`s3_0_c11_c0_{0,1}`) on the boot CPU and adds an FDT
`/memreserve/` for that range. Asahi's commit message says this region is 48
KiB on M4/M4 Pro/A18 Pro, is enabled only on secondaries, and together with
the WFI/WFIT avoidance makes SMP boot reliable.

## 0004: reserve iBoot's TrustCache region (local)

5012 measured the secondary-only write denial from the ADT's last page to at
least `adt_end + 256 KiB`, well past Asahi's 48 KiB CTRR_C range. The J614s
ADT's `/chosen/memory-map` names `[adt_end, adt_end + 0x60000)` as
`TrustCache`; the m1n1 image starts right after it. 0004 reserves that entry
by name (16 KiB-rounded `/memreserve/`) inside the same M4+ gate as 0001, and
logs and continues if the entry is missing. Together with the ADT and m1n1
reservations this covers the whole measured window, whatever CTRR_C reads.

0004 is AI-written (claude, 2026-10-31) and stays in this fork. Upstream
m1n1's `AGENTS.md` forbids AI-generated contributions, so never send it
upstream. It was written against upstream `main` at `1483995`, where 0001–0003
are already present. It passes a syntax-only clang check, and on 2026-10-31 0001–0006 were built natively
(gcc 12.2, `damsleth/m1n1` `80badc91` and `main` `214f93d`); not run on hardware. Review: `evidence/2026-10-31-review-5015-0004-codex.md`.

## 0005 and 0006 (local, 2026-10-31)

0005 reserves the other firmware regions iBoot names in `/chosen/memory-map` next to the
TrustCache: RTBuddySeg, SEPFW, SEPPatches, uStuff, preoslog, BootArgs. `dt_set_sep()` would reserve
SEPFW only with a `sep` node in the DT, which J614s lacks. It is hygiene, not the 205 fix (205 is a
permission fault, the CTRR signature). 0006 is optional and separate: m1n1 sets the `+0x4`
started-cores bit as `1 << (4 * cluster + core)`, but macOS takes it from the PMGR `clusters` table
(`bitpos + core`), which is E 4@0, P 6@4, P 6@10 on J614s, so the five P1 cores get bits 8..12
instead of 10..14. 0007 replaces the `ADT_GETPROP_ARRAY` reads of 0004 and 0005 (that macro copies the whole property before checking its length; found in an independent review, not reachable with real J614s data) with a length-first helper and one table. Apply 0001–0005, then 0007, then optionally 0006 (different files). Both 0005 and 0006 are AI-written and stay in this fork. Evidence and objects:
`evidence/2026-10-31-t6040-5015-m1n1-reservation-objects.md`.

## Prerequisite

0001 is gated on `!cpu_features->apple_sysregs_unlocked` (T6040's cores use `features_m4`, which
does not set it, so the block runs on J614s; checked 2026-10-31). That comes from
Asahi's June 2026 `cpu_features` work (`f3f2ca0` P_GET_CPU_FEATURES, `29073cce`
"chickens: rename cyc_ovrd to apple_sysregs_unlocked"). If our fork predates
it, `git am` will fail on 0001. In that case either rebase onto it, or, for a
T6040-only test object, replace the condition with `chip_id == T6040`.

## End-address caveat

Asahi uses `ro_end = ALIGN_UP(UPR, SZ_4K)`. Gravity's equivalent
(`GravityLinux/bootloader` `eb6cab7`) uses `ALIGN_UP(UPR + SZ_4K, page_size)`,
which treats UPR as the base of the last protected page (inclusive). With our
16 KiB-page kernel, memblock keeps any partly reserved page, so both forms
cover the same pages. On a 4K-page kernel, the Asahi form could miss the last
page. Gravity also refuses to boot if the range lies outside DRAM. Before the
5015 rig run, confirm the UPR semantics from the per-core read in step 2: is
UPR the last byte, the last page, or exclusive?

## Status

Exported 2026-10-29 (0001–0003), written 2026-10-31 (0004–0006). Applied and built on the M4 (three
standalone objects, none booted); `damsleth/m1n1` itself does not carry them yet. See
`evidence/2026-10-29-gravitylinux-survey.md` and ticket 5015.
