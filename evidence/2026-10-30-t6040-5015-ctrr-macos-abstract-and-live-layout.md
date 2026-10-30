# 5015: CTRR facts from the macOS kernel, plus the live memory layout (2026-10-30)

Sources: wallace-rex Pipeline B (private, commits `7f106b0` and `5495c18`; this file is its public-safe
abstract: no Apple strings, symbols or disassembly), and read-only reads on the running M4
(5019 kernel: `/sys/firmware/fdt`, `/proc/device-tree`, `/proc/iomem`, `/proc/cpuinfo`).
Everything here is a hypothesis until the rig confirms it.

## From reading the macOS kernel

1. **macOS writes no CTRR register on any CPU.** That covers `[3,0,11,0,0..3]`,
   `[3,0,11,1,0/1/4/5]`, the ACC_* set, and the legacy `s3_4_c15_c2_2..5`. The secondary-only
   window is set and locked by firmware before the OS runs. There is no unlock or init
   sequence to copy, so the only Linux-side remedy is keeping allocations out of the range
   (a carve-out). This matches 5012's framing.
2. **One range is read, never written.** At boot macOS reads `[3,0,11,1,2]` (lower) and
   `[3,0,11,1,3]` (upper) as the bounds of its own read-only kernel data. It treats the upper
   value as **inclusive at 4 KiB granularity**: the last byte is `UPR + 0xfff`. Which end
   Linux should reserve depends on the raw value. If UPR's low 12 bits are zero, the
   exclusive end is `UPR + 0x1000`, rounded up to 16 KiB, and Asahi's `ALIGN_UP(UPR, 4K)`
   is one page short. If UPR already ends in `0xfff`, Asahi's end is right. Step 2 records
   which case applies. In Asahi `442c7a2` naming this pair is the
   D instance (EL2 encoding); the secondary-only one is C.
3. **No IMPDEF sysreg or TLBI in the early CPU boot text.** Its TLB maintenance is
   inner-shareable only. This covers the early boot text only. The C-level per-CPU init was
   not traced, and the kernel does touch SPRR/GXF-style registers (`s3_6_c15_c1_*`, `c2_*`)
   and a large `s3_7_c15_*` block. If step 3 still faults with the reservation, that
   per-CPU init and the PMGR CPU-start path are the next RE targets.

## Live layout on this boot (m1n1 `v1.6.0-wallace-80badc91`, iBoot `mBoot-18000.161.10`)

- **No CTRR reservation.** The FDT's 16 `/memreserve/` entries are: the m1n1 stage-2 image
  `0x100041e4000 +0x10c000` (every spin-table `cpu-release-addr` lies inside it), the initrd
  `0x1000c800000 +0x1530c00`, 13 × `0x10000` blocks from `0x1000dd34000` at a `0x14000` stride
  (one per secondary), and one `0x26dc9` blob at `0x1000de38000`. `/reserved-memory` has phram
  `adt` `0x100040f0000 +0x94000`, phram `m1n1_stage2.log` `0x105ce7a0000 +0x4000`, and
  ramoops `0x10300000000 +0x200000` (no-map).
- **This m1n1 predates the CTRR_C series.** `patches/m1n1-ctrr-c-v1` was exported on
  2026-10-29 (`788cdf6`) and has not been applied to the enrolled m1n1. That's inferred from
  dates plus the missing mem-rsv; the binary wasn't checked.
- **The ADT is `[0x100040f0000, 0x10004184000)`.** `[0x10004184000, 0x100041e4000)` = 384 KiB
  between the ADT end and m1n1's `_base` is ordinary allocatable System RAM in `/proc/iomem`.
  5012's secondary-only write denial and every captured first-fault page (`adt_end+0`) fall in
  this window.
- **Boot CPU** is `cpu@10100` (`cpu-release-addr` 0). There are 14 CPUs, all `spin-table`.

## WFI/WFIT/WFET on the shipped kernels

The CPU has FEAT_WFxT: `/proc/cpuinfo` lists `wfxt` and `ecv`. The daily kernels (2234baad,
5019) carry `flokli-code.patch`, which kbuild applies or fails the build on. With `idle=nop`
it skips the initial **WFIT** in `__delay()`, but the following **WFET** loop still runs.
The running cmdline has `idle=nop` and **no `arm64.nowfxt`**. So "WFI/WFIT avoidance" is
shipped, but WFET is not avoided. Gravity's and Asahi's SMP recipe uses both
`idle=nop arm64.nowfxt`, and the 6002 audit already said `idle=nop` alone is not enough on the
Asahi base. Whether WFET matters at `maxcpus=1` is unknown; for any SMP attempt (5015 step 3),
add `arm64.nowfxt`.

## Changes to 5015

- **Step 2 (reads only):** read on the boot CPU **and** one secondary: `[3,0,11,0,0..3]`,
  `[3,0,11,1,0..3]`, `[3,0,11,1,4/5]`. Treat UPR as inclusive and overlay the results on
  `[adt_end - 16 KiB, adt_end + 0x60000)`.
- **Step 3: two variants.**
  - (a) The Asahi series as it is.
  - (b) A Wallace m1n1 mem-rsv over the **fixed** span `[adt_end, adt_end + 0x60000)`
    (384 KiB), which covers everything 5012 saw whatever the registers say. Do not use the
    running m1n1's `_base` blindly: after a chainload the running stage can sit elsewhere.
    Use `_base` as the end only if it equals `adt_end + 0x60000`; otherwise keep the fixed
    span and print a warning.

  If (a) reserves under 48 KiB and still faults while (b) is clean, the window is larger than
  C alone (C+D, or a bigger C on T6040). The cmdline for both adds `arm64.nowfxt`.
- **Pass criterion addition:** log every fault **outside** the reserved span. The 2026-07-29
  `maxcpus=14` boot had a second fault about 7.9 MiB above adt_end, in a later worker after
  the first died; probably a cascade, but the window does not explain it. A fault outside
  the reservation means a second mechanism.
- If step 3 still faults with the reservation in place, the next RE target is the PMGR
  CPU-start path (tell wallace-rex Pipeline B).
