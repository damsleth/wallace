# 205: the first fault is always the page immediately after the ADT reservation

Date: 2026-10-25. Author: claude (Mythos Wallace session), offline, from
existing console logs only. Follows 5011 (negative) and feeds 5012.

## The observation

In every boot on record where the first 205 fault was captured with its
PTE, the faulting physical page is the **first page after the 592 KiB
`flash@…` reserved-memory region**, which is m1n1's `phram` reservation of
the Apple Device Tree (`kboot.c dt_setup_mtd_phram`: `flash@<adt>`,
label `adt`, size `ALIGN_UP(devtree_size, 16K)`). iBoot places the ADT at
a different address each boot; the fault follows it.

| Boot | ADT reservation (`OF: reserved mem … flash@`) | first fault PA | CPU, time |
|---|---|---|---|
| 2026-07-29 maxcpus=14 (`smp-maxcpus14-console-20260729.log`) | `0x10005eb8000..0x10005f4bfff` | `0x10005f4c000` | CPU 6, 34 ms |
| 2026-10-25 5011 control 6a | `0x10004584000..0x10004617fff` | `0x10004618000` | CPU 5, 22 ms |
| 2026-10-25 5011 siq 6a | `0x10005b08000..0x10005b9bfff` | `0x10005b9c000` | CPU 5, 21 ms |

Three for three, `fault PA = reservation end + 1`. All three are the
async initramfs unpack (`copy_folio_from_iter_atomic` →
`__pi_memcpy_generic`) writing a freshly allocated page-cache page; the
printed PTEs are valid, AP=RW, DBM, no CONT. The July log's second fault
(CPU 7, 100 ms, `0x10006724f90`, kernfs) is 7.9 MiB higher and is the
next worker after the first died; it is not adjacent to anything
reserved. The July-29 threshold doc's fault (`0x100046c8000`) has no
reserved-mem lines preserved, so it cannot be placed.

m1n1 base in the two 5011 boots was `0x10004678000` and `0x10005bfc000`,
so the page is also exactly `base − 0x60000` both times; that is the same
fact seen from the other side (iBoot's layout is ADT, 384 KiB of something,
then the m1n1/kernelcache image), not an independent one.

## What it does and does not say

- The page is ordinary RAM to Linux: inside the single memory node
  (`0x100032a8000..`), not reserved, handed out by the buddy allocator.
  Nothing in the kernel ever maps it read-only: with `rodata=full` the
  linear map is created RW at page granularity, and the only early
  permission change is `mark_linear_text_alias_ro()` in `smp_cpus_done()`
  (`arch/arm64/kernel/smp.c:444`), which covers the kernel text alias at
  `0x1000f600000+`, not this page. So a stale read-only TLB entry for this
  VA has no Linux-side origin, which 5012's stages will test directly.
- Two readings remain, and they are now separable:
  1. **Page-specific.** Something outside Linux's page tables makes this
     physical page (and perhaps a range beyond the ADT) unwritable from
     some cores: a per-core physical protection in the CTRR/KTRR family
     (`s3_4_c15_c2_{2,3,4,5}` in XNU's naming, not in m1n1's
     `cpu_regs.h`, hence not in the 5010 named set), or a memory-system
     lock keyed to iBoot's layout. If the granule were 64 KiB, both 5011
     pages fall inside a range that ends at the ADT's rounded-up end.
     Under this reading the page is deterministic because the allocator's
     first page for the unpack worker is deterministic given the layout,
     and the fault is per-core because cpu 0 never writes it (it does the
     unpack itself only at `maxcpus=1`, and reaches userspace there).
  2. **Core-specific, page-coincidental.** The first page the first
     secondary worker touches is simply this one, and any page would fault.
     Then July's second fault at `+7.9 MiB` is the same mechanism on a
     different page, which fits; but 5010 found no named per-core
     configuration difference.
- The discriminator is a per-CPU write probe of *this* page, which 5012
  can add (§ below), or a two-instruction m1n1 test on the chainloaded
  proxy (cpu 5 MMU-off `ldr; str` of the same value to `adt_end`, then
  cpu 0): a fault with the MMU off is a physical protection; success is an
  MMU-level cause.

## Additions proposed for 5012 (`patches/t6040-205-fault-tlbi-retry-diag.patch`, `fb9663b5…`)

1. In stage 1 and stage 4, before retrying/Oopsing, execute `AT S1E2W`
   on the VA (the kernel runs at EL2 with E2H, so S1E2W is the current
   regime and privilege; log `S1E1W` too if cheap) and print `PAR_EL1`.
   `PAR.F=0` with the store still faulting means the stage-1 translation
   permits the write and the denial comes from outside the page tables
   (reading 1); `PAR.F=1, FST=permission` means the walker/TLB itself
   denies it, and the stage-2/3 outcome then says whether maintenance
   clears it.
2. A read check at stage 4: `copy_from_kernel_nofault` of the same VA.
   Read-OK/write-fault narrows to write permission.
3. A `postcore_initcall` probe (runs after `smp_init`, before the
   `rootfs_initcall` unpack): find the `phram` reserved-memory node labelled
   `adt`, take the page after it with `alloc_contig_range` (fails harmlessly
   if already in use), and from every online CPU via
   `smp_call_function_single` do a `copy_to_kernel_nofault` write-back of
   the page's own first word; log `cpuN: ok|EFAULT`. Then free it. Same for
   one unrelated free page as control. This maps "which cores can write
   page X" before any Oops and separates the two readings in one boot.
4. Log the fault PA's offset from the `adt` reservation end in the stage-1
   line (or leave it to the evidence; the logs carry both).

## Sources

```text
linux-build-out/siq-5011/{control-n6-a,siq-n6-a}/dcuart-{chainload,boot,console}.log  (m1n1 base, reserved mem, fault lines)
linux-build-out/smp-maxcpus14-console-20260729.log:18-19,203-215,351-363
m1n1 src/kboot.c:2731-2745 (dt_setup_mtd_phram), src/chainload.c (new_base = running base)
linux arch/arm64/kernel/smp.c:444 (mark_linear_text_alias_ro in smp_cpus_done), arch/arm64/mm/mmu.c map_mem
```
