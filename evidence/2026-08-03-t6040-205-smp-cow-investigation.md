# Ticket 205: SMP copy-on-write corruption — first investigation round

The single blocker for a multi-core daily driver on t6040. Reproducer, threshold, and one
hypothesis refuted.

## Reproducer (fast, reliable, no enrollment)

```
EXTRA_BOOTARGS='maxcpus=N console=ttydc0 sdroot.shell'   initramfs-sdroot.cpio.gz
```

`sdroot.shell` switch_roots into the SD root and execs a bare shell instead of `/sbin/init`, so the
**first** userspace copy-on-write either survives or panics within ~4 s. Verdict in one boot.

## Threshold: 2 is the limit, and severity scales with core count

| maxcpus | `sdroot.shell` | full `/sbin/init` |
|---|---|---|
| 1 | clean, 0 traces, 0 panics (repeated) | **clean** — OpenRC, dbus, bluetooth, shell, persistence verified |
| 2 | clean, 0 traces | **runs**, but 2 traces: an exFAT writeback warning and a process killed by `arm64_force_sig_fault` → `make_task_dead` |
| 3 | **PID 1 SIGSEGV → panic** (`exitcode=0x0000000b`) | — |
| 4 | PID 1 SIGSEGV → panic | — |
| 5 | hang | hang |

So this is not a clean on/off threshold: at 2 CPUs the fault still fires but lands on a
non-init process, so the machine survives while random processes die. **maxcpus=1 is the only
configuration that is actually clean**, and that is what the daily driver should use for now.

## The fault

```
CPU: 2 UID: 0 PID: 1 Comm: busybox Tainted: G S
pc : copy_page+0x48/0xc4
lr : copy_highpage+0x70/0x21c
x1 : ffff800012360080   x0 : ffff800004624100     (both kernel linear-map)
Call trace: copy_page → copy_user_highpage → do_wp_page
```

Kernel-mode fault while copying a page for CoW; the victim process gets SIGSEGV. When the victim is
PID 1 the kernel panics; otherwise the process just dies.

## REFUTED: intra-cluster sharing

Hypothesis: the corruption needs two CPUs inside one cluster (shared L2), since maxcpus=2 happens to
be P00 + one E core (two different clusters) while maxcpus=3 adds a second E core to cluster 0.

Test: `dts/t6040-j614s-dcuart-onepercluster.dts` fails every E core but E0 and every P0 sibling, so
the first three CPUs are one per cluster. **DTB verified from the boot log:**

```
CPU1: Booted secondary processor 0x0000000000 [0x611f0541]   <- E core,  cluster 0
CPU2: Booted secondary processor 0x0000010200 [0x611f0551]   <- P core,  cluster 2
smp: Brought up 1 node, 3 CPUs
```

Result: **still panics**, same `copy_page` fault. Three CPUs in three different clusters fault just
as readily as three CPUs in two. Cluster placement is irrelevant; it is core *count*.

## Also refuted: non-temporal store hazard

The faulting instruction looked like `stnp` on a hand-decode, which would have been a promising
Apple-core hazard. It is not: `arch/arm64/lib/copy_page.S` in this tree uses plain `ldp`/`stp`
throughout. Do not pursue the non-temporal angle.

## Next lines of attack

1. **A minimal C reproducer** (fork + touch shared pages in a loop) runnable at maxcpus=2, where the
   system survives. That decouples the bug from the boot machinery and makes it reportable upstream.
   This is the highest-value next step: everything so far needs a full boot per data point.
2. **`idle=nop` interaction.** We always boot `idle=nop` because M4 loses CPU state on WFI, so every
   idle core *spins* instead of sleeping — that is unusual and changes memory-system behaviour with
   core count. Try `idle=yield` (does not sleep, so it should be safe on M4) at maxcpus=3.
3. **Cache maintenance around CoW**: `copy_highpage` on arm64 also copies page *tags*/flags; check
   whether anything in that path needs an Apple-specific barrier or D-cache maintenance, and whether
   the Asahi tree carries a patch we are missing.
4. **Ask upstream/yuka whether t8132 shows this.** If M4 has an erratum here it may already be known;
   our tree is a t6040 port of untested M4 support, so we may simply be missing a workaround.

## Practical consequence

A **complete persistent Alpine daily driver exists today at maxcpus=1** (ticket 204): i3, WiFi, BT,
cpufreq, RTC, keyboard backlight, and a real root filesystem on the SD card that survives reboots.
Going multi-core is now this one well-scoped kernel bug.

---

# Round 2: a dependency-free reproducer, and a controlled 1-vs-2 result

## The reproducer (`scripts/t6040-cow-repro.sh`)

No toolchain needed — pure busybox. Fork N children that each write to a large inherited heap,
forcing `do_wp_page`/`copy_page` for every page:

```sh
X=$(dd if=/dev/zero bs=1024 count=512 2>/dev/null | tr '\000' 'a')   # 512 KB heap
i=0; while [ $i -lt 300 ]; do ( Y="${X}b"; echo "${#Y}" >/dev/null ) & i=$((i+1)); done; wait
```

## Controlled result — same loop, same heap, only core count differs

| maxcpus | traces before | traces after | loop finished? |
|---|---|---|---|
| 2 | 0 | **3** | **no** — task killed |
| 1 | 0 | **0** | **yes** — `COW-LOOP-DONE-1CPU` |

The failing path, captured from the reproducer (not just the boot):

```
do_page_fault → do_bad_area → die_kernel_fault → arm64_force_sig_fault → make_task_dead → do_exit
```

`die_kernel_fault` confirms the fault is taken in **kernel mode**, matching the boot-time
`copy_page+0x48` / `copy_highpage+0x70` / `do_wp_page` signature.

**Why this matters:** every previous data point cost a full boot (~2 min). Now a single boot at
maxcpus=2 gives a shell where the bug can be triggered on demand in ~40 s, and the same script is
directly usable in an upstream bug report — no Wallace-specific boot machinery required.

## `idle=yield` HANGS the boot — hypothesis untestable this way

We always boot `idle=nop` because M4 loses CPU state on WFI, so idle cores spin; that is unusual and
scales with core count, making it a natural suspect. Testing it needed a boot-script fix first:
`t6040-boot-dcuart.sh` hardcoded `maxcpus=1 idle=nop`, so an `EXTRA_BOOTARGS` override produced
**two** conflicting copies on the cmdline (`maxcpus=1 … maxcpus=2`, `idle=nop … idle=yield`) and the
first attempt was inconclusive. Now overridable via `BOOT_MAXCPUS` / `BOOT_IDLE`.

With a clean `maxcpus=2 idle=yield` cmdline the kernel produced **zero console output** (20 lines,
m1n1 only) where `maxcpus=2 idle=nop` boots reliably. So `idle=yield` is not viable on this
hardware and the idle-loop hypothesis cannot be tested by swapping the idle method. It would need
either `idle=wfi` (expected to be worse — WFI is exactly what M4 mishandles) or an instrumented
idle path.

## Where round 2 leaves it

Confirmed: a real SMP-dependent kernel-mode fault in the CoW page-copy path, reproducible on demand
with a three-line shell script, clean at one CPU. Refuted so far: intra-cluster sharing, non-temporal
stores, and (as a testing route) the idle method.

Best next steps:
1. Take the reproducer to **upstream/yuka** — this is now a clean report and t8132 may already know it.
2. Instrument `copy_highpage`/`copy_page`: log the `x0`/`x1` page addresses and check alignment and
   whether the destination is a page the kernel should own; a `WARN_ON` on non-page-aligned or
   unexpected mapping would localise it fast, and the reproducer makes each attempt cheap.
3. Check the Asahi tree for any CoW/cache-maintenance patch we are missing in this port.

---

# Round 3: the instrumentation makes the bug DISAPPEAR (and the args are clean)

Added to `copy_highpage()` a `WARN_ONCE` validating exactly what `copy_page()` is about to be handed:
page-alignment of both addresses, `virt_addr_valid()` on both, and self-copy. Verified present in the
packed Image (`t6040-cow: bad copy_page` string).

Result at `maxcpus=2`, **four consecutive runs** of the reproducer in one boot:

| run | kernel traces | `t6040-cow` warns | loop completed |
|---|---|---|---|
| 1 | 0 | 0 | yes |
| 2 | 0 | 0 | yes |
| 3 | 0 | 0 | yes |
| 4 | 0 | 0 | yes |

The un-instrumented kernel faulted on the **first** run of the same loop at the same core count.

## Two conclusions

1. **`copy_page`'s inputs are always valid.** The WARN never fired once — both addresses are
   page-aligned, both are valid linear-map addresses, and source never equals destination. So the
   corruption is not a bad-argument bug; it is in the copy itself or in the state of the pages.
2. **A few instructions of work before `copy_page` suppress the race.** This is a Heisenbug. That is
   a *lead*, not just an annoyance: `virt_addr_valid()` performs memory reads (pfn/sparsemem
   lookups), so the fix-by-accident is consistent with a **missing barrier or cache maintenance
   before the CoW copy** — e.g. the destination page's prior contents (zeroed or written by another
   CPU) not yet visible to the copying CPU.

## Attribution caveat

The faulting runs were on the build immediately *before* the instrumentation commit — same tree
otherwise. Attribution to the instrumentation is reasonable but not airtight, since any rebuild can
shift codegen. A control run of the un-instrumented Image in the *same* session should confirm it
(ticket 208).

## The experiment this sets up

Bisect *what* suppresses it, from cheapest to most meaningful (ticket 207):
`smp_mb()` alone → a single dummy read of `kto` → `dcache` maintenance on the destination →
nothing (control). Whichever minimal operation makes the fault go away names the missing primitive,
and that is directly upstreamable.

---

# Round 4 (ticket 208): the control PASSES — the Heisenbug is real

Reverted the instrumentation, rebuilt (verified: `t6040-cow` string absent from the Image), and ran
the identical reproducer 4x at maxcpus=2 in one boot.

| build | traces over 4 runs |
|---|---|
| instrumented (`WARN_ONCE` before `copy_page`) | **0** |
| un-instrumented (control) | **2** |

So the suppression is attributable to the instrumentation, not to build luck or the machine changing.
**Ticket 207's bisect is valid** — there is a real, minimal operation that makes this fault vanish,
and finding it names the missing primitive.

Two refinements from the control run:

- The fault fired only in the **first** run of the four; runs 2-4 were clean. That points at a
  first-touch / settling effect (fresh anon pages, cold caches, or a cluster that has not yet been
  scheduled on) rather than steady-state corruption. **Any future single-run "clean" result is
  therefore weak evidence** — repeat counts matter, and a clean run 1 is the meaningful signal.
- The loops **completed** in the control: the victim was a child process, not the parent shell. That
  is consistent with the maxcpus=2 daily-driver observation (system survives, random processes die)
  and with maxcpus>=3 killing PID 1 and panicking.

## Method note for the whole ticket

Because the fault is timing-sensitive and first-touch-biased, every experiment from here on must:
1. record the trace count at a **fresh boot baseline**, then after each run;
2. run the reproducer **at least 4 times**, treating run 1 as the sensitive one;
3. never conclude from a single clean run.

---

# Round 5 (ticket 207): the barrier bisect — "missing barrier" REFUTED

Method per 208's rule: fresh boot, baseline trace count, then 4 reproducer runs at maxcpus=2.

| variant | change before `copy_page()` | traces / 4 runs |
|---|---|---|
| (e) control | nothing (un-instrumented) | **2** — faults |
| (a) barrier | `smp_mb()` only | **0** — clean |
| (b) read | `READ_ONCE(*(volatile unsigned long *)kto)`, **no barrier** | **0** — clean |

## Conclusion: it is not an ordering bug

Variant (a) looked like the answer — a bare barrier suppressed the fault, which would have been a
clean, upstreamable "arm64 CoW needs a barrier on Apple cores" result. Variant (b) kills it: a single
volatile read with **no barrier at all** suppresses it just as completely. So (a) demonstrated only
that *something* executes before `copy_page`, not that ordering was missing.

**Any small perturbation before the copy hides this fault.** Combined with round 3 (the WARN's
validation work also hid it) and round 4 (removing it brought the fault back), the honest conclusion
is that this is a **timing-sensitive race that is not located in `copy_highpage` at all** —
`copy_page` is where the fault is *taken*, not where the bug lives. Editing this function to make the
symptom go away would be papering over it, and I am not proposing that as a fix.

## What the evidence now points at

The fault is a **kernel-mode** fault (`die_kernel_fault`) on a **linear-map** address that
`copy_page` is legitimately reading/writing, with valid, aligned arguments (round 3). For a linear-map
access to fault at all, the mapping must have changed under us — which suggests a **page
lifetime/mapping** problem rather than a data-ordering one: the source or destination page being
freed, unmapped, or re-protected by another CPU while the copy is in flight. On arm64 with
`rodata_full` the linear map is page-granular and *can* be made invalid, so this is mechanically
possible.

That reframes the search away from `copy_highpage` and toward:
1. **Page refcount/lifetime in the CoW path** — is the destination page's reference held for the whole
   copy? A missing `get_page`/premature `put_page` would fit exactly.
2. **TLB invalidation completion** on this hardware — a broadcast TLBI that does not complete before
   the mapping is reused would produce faults on addresses that "should" be mapped.
3. **Upstream/yuka**: we run untested M4 support. This may be a known erratum with a known workaround
   that our port simply lacks. **The reproducer makes this a clean report** — that is now the single
   highest-value action, ahead of more local experiments.

## Do NOT do next

- Do not ship any of variants (a)/(b) as a fix. They hide the symptom, the mechanism is unknown, and
  (b) proves the suppression is not semantic.
- Do not conclude anything further from single runs; the fault is first-touch biased (208).

---

# Round 6: it is NOT CoW-specific — it is bulk memcpy, in every SMP topology

## The 2x2 on core type and cluster placement

All at maxcpus=2, `sdroot.shell`, topology verified from `Booted secondary processor` MPIDRs:

| DTB | CPUs online | same cluster? | same core type? | traces at boot | reproducer |
|---|---|---|---|---|---|
| default | P00 + E0 (`0x0`, midr `…0541`) | no | no | **0** | faults |
| `p2clusters` | P00 + P10 (`0x10200`, midr `…0551`) | no | yes | **1** | no new in 2 runs |
| `ponly` | P00 + P01 (`0x10101`, midr `…0551`) | **yes** | yes | **3** | +1 |

**Mixed core types is REFUTED** — a P-only pair faults, and faults harder than the mixed pair. Cluster
sharing is not the *cause* either (the earlier one-per-cluster test at maxcpus=3 panicked), but it is
clearly an **aggravating factor**: same-cluster is worst, and it is the only configuration that faults
during boot three times before any stress is applied.

So: **every** 2-CPU configuration is broken, in every combination of placement and core type. There is
no "safe" pairing to ship.

## The unifying observation: the victim is always a bulk memcpy

The P-only boot fault is **not** in the CoW path at all:

```
__pi_memcpy_generic+0x128/0x22c (P)
jbd2_journal_recover+0x164/0x1cc
jbd2_journal_load+0xb0/0x360
ext4_fill_super+0x17e8/0x2c1c
```

That is ext4 journal recovery during mount. Collect the three signatures seen so far:

| path | caller |
|---|---|
| `copy_page` | `copy_highpage` ← `do_wp_page` (copy-on-write) |
| `__pi_memcpy_generic` | `jbd2_journal_recover` ← `ext4_fill_super` (journal replay) |
| `copy_folio_from_iter_atomic` | `unpack_to_rootfs` (initramfs unpack, from the original 121 reports) |

Three unrelated subsystems, one common factor: **a large memory-to-memory copy running while another
CPU is active.** This retires "CoW bug" as a framing — CoW was simply the first path the reproducer
happened to hit. Ticket 205's title and 121's framing should both be read as "SMP bulk-copy
corruption".

## What this points at now

A fault that appears in *any* bulk copy, in *any* SMP topology, on addresses that are validly mapped
(round 3) and with alignment/validity proven, and which a few instructions of delay can hide
(rounds 3-5), looks like a **coherency or CPU-init problem rather than a bug in any of these callers**.
The most promising untested area is therefore **the state secondary CPUs are started in**: this port
brings them up via `spin-table` out of m1n1, and if a secondary begins executing with cache, MMU,
MAIR/TCR or Apple-specific (SPRR/GXF/APRR) state that does not match the boot CPU, its view of memory
would be incoherent in exactly this way — large copies corrupting or faulting, small ones usually
getting away with it.

Next: compare m1n1's secondary-CPU entry state against what `secondary_start_kernel` assumes, and
check whether the Asahi tree carries M4 secondary-boot handling this port lacks. That is offline work
and does not need the rig.

## Round 6 addendum: silent-corruption test INCONCLUSIVE

Attempted to distinguish *silent data corruption* from *faults only* — a genuinely important
property, since silent corruption would mean a coherency bug while fault-only points at mapping or
lifetime. Test: 6 iterations of `dd 16 MiB from /dev/urandom` → `md5sum` → `cp` → `md5sum`, comparing
hashes, on the `p2clusters` (P00+P10) boot at maxcpus=2.

**The test did not complete** — the session died before reporting. The console then showed a boot
panicking at 3.74 s (`Attempted to kill init! exitcode=0x0000000b`), i.e. the machine had restarted
and a subsequent SMP boot failed in the usual way. So no verdict on silent corruption, and no
evidence that this particular test caused the death rather than merely coinciding with it.

**Do not read this as "16 MiB copies crash the machine"** — the working hypothesis needs a rerun with
the transcript preserved before each step, ideally at maxcpus=2 with the reproducer's known-good
harness rather than a long-running loop that can lose its output when the victim is the shell.

Also worth noting for whoever picks this up: `maxcpus=2` is where experiments *can* run (the system
survives) but the shell itself is a candidate victim, so any multi-minute test needs its output
streamed to `/dev/kmsg` line by line, not buffered to the end.
