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
