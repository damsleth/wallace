# 5012 (claude, 2026-10-25): the secondaries' MMU denies writes around the ADT; boot core allows; not TLB, not CTRR

Faultdiag kernel `737df0b0` (two identical builds; config == daily301
`96e83d85`), patch `t6040-205-fault-tlbi-retry-diag.patch` at 7c01a45.
Harness: thin dcuart DTB, 217 initramfs-cow-report, control m1n1 `bf4b2462`,
maxcpus=6. Reviews: Codex (fix-first, applied) and Mythos (PASS plus additions,
applied). Consoles: `2026-10-25-t6040-5012/console-n6-{a,b}.log`.

## Early probe (postcore, before the initramfs unpack): `AT S1E2W` per CPU

Boot a: ADT `[0x10004b74000-0x10004c07fff]`. Boot b: ADT
`[0x100047c4000-0x10004857fff]`. Both boots gave the same result:

| page | cpu0 (boot P) | cpu1-4 (E) | cpu5 (P) |
|---|---|---|---|
| adt_last, adt_end+0/+1/+2/+3, adt_end+16 | `PAR ff00…b80`: write OK, normal WB | **`PAR 0x81f`: F=1, FST 0x0f, level-3 permission fault** | **`0x81f`** |
| control (alloc_page, `0x10003a58000`) | OK | OK | OK; nofault read and write-back OK on every CPU |

The page after the ADT was "not allocatable" in both boots (in use), so only
the PAR-only pass covered it.

## The real fault (both boots identical)

CPU 5, `__pi_memcpy_generic+0x128` (async initramfs unpack), VA = adt_end+0,
PA(lin) = PA(pte), PTE `00e801…707` (writable), ESR `0x9600004f`,
`PAR 0x81f`. Plain retry, then local TLBI, then broadcast TLBI: **every
retry faulted again**. A nofault read of the same VA is **ok**.

## CTRR registers (5010 tooling, reads only, `ctrr-sysregs.json`)

Identical on cpu0, cpu1 and cpu5: `CTRR_CTL_EL1/EL2 = CTRR_LOCK_EL1/EL2 =
0x8000000000000001` (enabled and locked), A range
`0x1000000c000-0x100002d7000`, every EL12 and B register 0. The CTRR range
does not cover the ADT neighbourhood, and the values do not differ by core.
**CTRR is not the 205 cause.** (The range itself is low memory that iBoot has
locked against writes; note it for Linux memory use.)

## Reading

- The fault is **not a stale TLB entry**. TLB maintenance at any scope does
  not clear it, and `AT` reproduces the denial on demand.
- It is **core-specific**. Every secondary denies writes and the boot core
  allows them, for the same VA and the same page tables.
- It is **region-specific**. The denied window runs from the ADT's last page
  to at least adt_end+16; a page about 18 MiB lower is fine everywhere. With
  16 KiB pages one level-3 table covers 32 MiB. The denied pages share one
  L3 table (`0x10004000000-0x10005ffffff`); the control page uses another.
- Candidates: (a) the secondaries' table walker sees a different
  (read-only) version of that L3 table page than cpu0 does, i.e. a
  walk-coherency or stale-memory problem for page-table pages; (b) another
  permission mechanism applied by a translation-time range check on the
  secondaries only (SPRR/APRR-style, PPL/GXF-style or similar), configured by
  iBoot or by reset for that physical window.
- Next discriminators: AT on more pages across the 32 MiB block and its
  neighbours, to find whether the edge matches an L3-table boundary
  (supports a) or a physical range; a read of the L3 descriptor from a
  secondary through an uncached alias, against cpu0's view; and Mythos's
  MMU-off physical str on a secondary (a separate write class, CJ approval
  first).

## Probe v2 (2 boots, kernel `c4199a1d`, patch at 412dc15; Codex and Mythos reviewed)

- **Translation registers are identical on all 6 CPUs:** TTBR0 `10011bb0000`,
  TTBR1 `10011bb4001` (equal to init_mm.pgd `10011bb4000`), TCR
  `11000737551b511`, SCTLR `2000018fc74f99d`, MAIR `40044ffff`, HCR `488000038`,
  VTCR `80038000`. MMFR3 is 0, so there is no TCR2/S1PIE/POE.
- **Every CPU loads identical walked descriptors.** Boot a: pud `@10011bb4000
  = 18000105ce798403`, pmd `@105ce798010 = 18000105ce790403`, pte
  `@105ce791100 = 00e8010004880707` (writable). Four distinct entries; pgd is
  folded.
- **Coherency test NEGATIVE.** The control (flush_tlb_all, then AT) and the
  test (cpu0 `dcache_clean_inval_poc` of all 4 descriptor lines, `dsb sy`,
  flush_tlb_all, then AT) give the same result: cpu0 OK, cpu1–cpu5
  `PAR 0x81f`. So it is not stale page-table memory and not a stale TLB.
- **AT grid** (boot a; boot b the same, with the ADT elsewhere):
  - **OK on every CPU:** the 32 MiB L3-table boundaries b0 and b1 with
    neighbours, ADT−8 MiB, ADT+8 MiB, b1+32 MiB and ADT+64 MiB.
  - **Denied on every CPU, cpu0 included:** b0−2 pages and b0−1 page
    (`0x10003ff8000/0x10003ffc000`). This is a separate, uniform read-only
    area and not the secondary-only effect.
  - **Denied on secondaries only:** adt_end (and the earlier window,
    adt_last to adt_end+16).
- **Conclusion: Mythos's reading (b).** A per-core, translation-time write
  denial on a **physical range** around the ADT end, applied by the
  secondaries only. It is not tied to the L3 table page; its extent is more
  than 256 KiB and less than ±8 MiB.
- Layout from iBoot's boot args (boot b): `phys_base 0x100032a8000`, ADT
  `0x10004b20000-0x10004bb3fff`, rollback m1n1 base `0x10004c14000`
  (= adt_end + 0x60000), boot_args at `0x100052d8000`, `top_of_kdata
  0x100052dc000`.
- Next (v3): an exact per-CPU AT bitmap over ADT ±32 MiB at 16 KiB steps,
  logged as runs. That names the range and lets it be checked against the
  boot-args layout. It is also the basis for a reserved-memory workaround,
  which would be a carve-out, not a fix.
