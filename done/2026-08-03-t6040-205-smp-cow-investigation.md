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
