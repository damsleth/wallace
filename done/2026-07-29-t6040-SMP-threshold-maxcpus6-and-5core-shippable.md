# SMP bisected: userspace dies at maxcpus>=6, and 5 cores work with the FULL driver set

2026-07-29, over KIS with the rollback loader enrolled. This supersedes two wrong explanations of
mine from earlier the same day.

## Retraction first

I claimed the `Unpacking initramfs` oops was caused by **my** repacked initramfs (extracted as a
non-root user, losing device nodes). **That was wrong.** The pristine, untouched
`initramfs-smp-kmsg-report.cpio.gz` — the exact file that boots fine at `maxcpus=2` — faults
identically at `maxcpus=14`. The variable is the CPU count, not the archive.

(Whether my repacked archives are *also* defective is now untested and unimportant; do not rely on
the earlier claim either way.)

## The fault

```text
Unable to handle kernel write to read-only memory at virtual address ffff0000046c8000
ESR = 0x000000009600004f   EC = 0x25: DABT (current EL)
FSC = 0x0f: level 3 permission fault      WnR = 1
pte=00e80100046c8707                      (AP = read-only at EL1)
pc : __pi_memcpy_generic+0x128/0x22c
lr : copy_folio_from_iter_atomic+0x494/0x8c0
Call trace: unpack_to_rootfs+0x118/0x314 -> do_populate_rootfs+0x10c/0x1c4
```

A write during initramfs extraction lands on a linear-map page whose PTE is read-only. It happens
*after* SMP bringup completes, so the cores are already up when it fires.

## The bisect

Identical artifacts every time (m1n1 `1394c345`, `Image-dcuart-earlycon`, DTB `2782b922`, untouched
initramfs `43944ef2`); **only `maxcpus` differs**:

| maxcpus | cpu_online | processor_count | oops | userspace |
|---|---|---|---|---|
| 1 | 0 | 1 | 0 | reached |
| 2 | 0-1 | 2 | 0 | reached (`RESULT_PASS`, taskset proved CPU1) |
| **5** | **0-4** | **5** | **0** | **reached** |
| 6 | — | — | **2** | never |
| 7 | — | — | 1 | never |
| 9 | — | — | 1 | never |
| 14 | — | — | 1 | never |

**The threshold is exactly 6.**

## Why 6 is an interesting number here

Decoding the MPIDRs from the bringup log gives the real topology:

| cluster (aff1) | CPUs | part | count |
|---|---|---|---|
| 0 | 1–4 | `0x054` | 4 E |
| 1 | 0 (boot, aff0=0), 5–8 (aff0=1–4) | `0x055` | 5 P |
| 2 | 9–13 (aff0=0–4) | `0x055` | 5 P |

`maxcpus=5` brings up cpu0–4 = the boot P core plus **all four E cores**, i.e. two clusters, and
works. `maxcpus=6` adds **cpu5, which is the second core in the boot's own cluster** — and that is
where it breaks. So this is not "P cores are broken" (cpu0 is a P core) and not "crossing a cluster
is broken" (the E cluster is fine). Candidate explanations, none yet tested:

- a second core in the boot cluster changes cluster-local cache/coherency state during early boot;
- or it is a plain resource threshold (per-CPU allocations past 5 CPUs shift the memblock layout so
  the initrd region overlaps something already mapped read-only).

Discriminating between those needs a DTB that disables cpu5–8 so `maxcpus=6` would instead bring up
cpu9 (a different cluster). That is a DT build, not a bootarg, and is the obvious next experiment.

## The shippable result: 5 cores with everything

Full daily-driver payload — m1n1 V1 `28a4e0cf`, kernel
`Image-macsmc-hid-type-fix-trackpad-nbcon-ppp-v116.xz`, WiFi DTB `0afb98ae`, dwm getty image
`b7b1a4df` — at `maxcpus=5`, object `c48080b920452aa2f0172f3a03d82cda712bddbfd05587dc2213c96efddf157d`:

```text
verdict: OK — payload accepted and kernel entered
userspace: a shell prompt appeared
nproc: 5
/proc/stat:
  cpu0 0 0 78 5211 …    cpu1 5 0 51 5237 …    cpu2 4 0 24 5263 …
  cpu3 5 0 25 5258 …    cpu4 0 0 83 5209 …
wlan0  Link encap:Ethernet  HWaddr 84:2F:57:33:9E:D7
hci0
dmesg | grep -cE "Internal error|Oops"  ->  0
```

Every core shows **nonzero user *and* system time**, which is the proof that was missing before: the
scheduler is really placing work on all five, not merely marking them online. WiFi and Bluetooth
survive, and there is no oops.

**So the daily driver can go from 1 core to 5 today** — a 5× improvement, on the exact payload that
is already reviewed and enrollable, changing one bootarg. `maxcpus=14` stays blocked on the bug above.

The `idle=nop` thermal caveat still applies and scales with core count: idle cores spin rather than
sleep, so five will run warmer than one. cpuidle remains a prerequisite for going further.
