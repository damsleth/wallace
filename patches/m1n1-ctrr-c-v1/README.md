# m1n1 CTRR_C secondary-only reservation (ticket 5015)

These are verbatim `git format-patch` exports from AsahiLinux/m1n1 `main`, with
the original authors kept:

| Patch | Upstream | Author |
|---|---|---|
| 0001 | `a735ea2` kboot: add reserved CTRR_M4 region | Yureka |
| 0002 | `442c7a2` cpu_regs: Add CTRR/CTXR sysregs used by SPTM | Sven Peter |
| 0003 | `00b8814` kboot: Fix M4* boot under hypervisor | Janne Grunau |
| 0004 | local, not upstream | CJ Damsleth (AI-written, see below) |

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
are already present. It passes a syntax-only clang check; it has not been
built or run. Review: `evidence/2026-10-31-review-5015-0004-codex.md`.

## Prerequisite

0001 is gated on `!cpu_features->apple_sysregs_unlocked`. That comes from
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

Exported 2026-10-29 (0001–0003) and written 2026-10-31 (0004). Not applied to the fork, built or run. See
`evidence/2026-10-29-gravitylinux-survey.md` and ticket 5015.
