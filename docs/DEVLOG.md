# T6040 / J614s development log and operating notes

Current as of 2026-08-19. This file keeps durable operating knowledge,
milestones, corrections, and dead ends. Exact experiment evidence lives in
`evidence/`; current work lives in [NEXT_STEPS.md](NEXT_STEPS.md).

Live capability status is in [NEXT_STEPS.md](NEXT_STEPS.md) §0 (the single
source of truth); this file records the durable *how* and *why* behind it —
solved blockers, corrections, and dead ends. Per-experiment evidence lives in
`evidence/`.

## Operating the rig

### Lease first

Only the lease holder runs a rig script, and only for an approved, ready
ticket. Release `wedged` if recovery is incomplete or uncertain. The canonical
protocol and commands are in [COORDINATION.md](COORDINATION.md).

**Each concurrent session needs a DISTINCT lease handle.** `rig-lease.sh
acquire` on a lease already held by the same handle silently renews and relabels
it (it does not refuse), so a colliding handle clobbers the other session's
active-run record. Use your own handle; never `acquire` under one another live
session is using. Canonical handle list and protocol in
[COORDINATION.md](COORDINATION.md).

### DebugUSB/KIS discipline

`scripts/t6040-debugusb-console.sh reboot` starts kisd, puts its PTY into raw
mode, attaches a reader, enters DebugUSB, and waits for `Running proxy`.
`/tmp/m1n1` is the proxyclient device.

Rules:

1. A fresh PTY must be raw and drained. An unread boot stream fills the PTY
   buffer and makes KIS appear one-way.
2. Do not leave a separate reader active while proxyclient owns the PTY; it
   steals binary replies. The Wallace helpers stop and restore their reader.
3. Every successful Linux chainload consumes the proxy. Run a recovery cycle
   before every new chainload.
4. The first proxy attempt may see `UartCMDError` from residual bytes. Retry
   once after confirming the reader transition.
5. `Running proxy` normally appears in under 20 seconds. Minutes of silence
   indicate a broken observation path, not a reason to keep waiting.
6. Short-lived automation that launches a console helper uses
   `T6040_KEEPALIVE=1`; otherwise the parent may reap the helper group.
7. The proven DebugUSB port is left-back/HPM0. Do not involve it in right-port
   HPM experiments.
8. **Never leave a rig command polling in the background.** The rig is a single
   exclusive resource, so a stranded waiter becomes a second driver. On
   2026-08-03 a `until grep 'Running proxy'` loop was backgrounded after its
   reboot failed; when a later reboot printed that string the stale loop woke up
   and launched a *second* `boot-dcuart.sh` concurrently with the foreground
   one. Two proxyclients on one PTY produced
   `UartTimeout: Expected 1 bytes, got 0 bytes`. Wait in the foreground, or
   check for stragglers (`pgrep -f t6040-boot-dcuart`) before every boot.
9. `debugusb-console.sh reboot` leaves its own `cat /tmp/m1n1` reader running,
   and it fights whatever proxyclient runs next. `boot-dcuart.sh` detaches the
   old reader itself, so do **not** `pkill` it by hand — that only creates a
   window with no reader at all. Symptom of contention: a console log that stops
   at exactly m1n1's own output (~625 bytes / 20 lines) with nothing after
   `Vectoring to next stage`.

An empty ttydc0 transcript is not proof of a kernel hang. Reattach kisd,
confirm the proxy or a known console control, and preserve the first complete
transcript before reboot.

### Standard loop

The recovery, chainload, console, raw-object, build, enrollment, and
inspection commands live in [RUNBOOK.md](RUNBOOK.md); this file records only
the discipline around them.

## Build invariants

- The kernel builds in the `kbuild` container on a case-sensitive volume.
- Builds use committed kernel code plus copied T6040 DT files. Code changes
  must be patches consumed by `scripts/t6040-kbuild.sh`.
- Claim reproducibility only after two clean byte-identical builds.
- Enrolled raw objects must be a multiple of 16 KiB.
- XZ members are one stream, one block, CRC32, and no BCJ.
- The project initramfs expansion policy is 128 MiB.
- The strict verifier pins every member and embedded bootargs.
- Never repack a root filesystem from an extraction that lost device nodes or
  ownership.
- **`$OUT/Image` is what boots, and nothing keeps it in sync with the named
  `Image-<config>` artifacts** — it can silently be weeks old. `boot-dcuart.sh`
  refuses a kernel with zero `pcie-apple` or `macsmc` (override
  `BOOT_SKIP_IMAGE_CHECK=1`); the by-hand verification commands are in
  [RUNBOOK.md](RUNBOOK.md) §5b. When grepping a binary for a driver marker,
  confirm the grep works by also matching a control string — a wrong grep hides
  the very line that disproves your theory.
- **A whole missing *subsystem* means the wrong kernel, not broken hardware.**
  One absent device can be hardware; an empty `/sys/bus/pci/devices` cannot.

## Durable bring-up results

### Core boot

- T6040 CPU-start offset `0x88000` and the 4E+5P+5P topology are verified.
- Locked system-register accesses require the T6040 AIC/idle handling carried
  by the Wallace patches.
- DAPF entries that trap on T6040 are skipped while the required MTP DART path
  remains available.
- PMGR generation and the current power-domain layout are sufficient for boot.
- The watchdog transfers from m1n1 to Linux.

### Boot object and enrollment

- Direct raw m1n1 is sufficient; U-Boot is optional.
- The object layout is m1n1 plus bootargs, compressed kernel, DTB, compressed
  initramfs, and terminator.
- The former enrolled-boot reset loop was caused by total object length not
  being 16 KiB aligned.
- Alpine and Ubuntu RAM roots boot untethered.
- The dual-mode loader provides a short USB-serial window and otherwise boots
  normally.

### Display and keyboard

- simpledrm and fbcon use the framebuffer handed off by m1n1.
- Xorg’s modesetting driver works without accelerated graphics.
- The first Xorg failures were missing `CONFIG_UNIX` and a missing udev
  runtime, not a simpledrm limitation.
- Internal keyboard registration required a DockChannel HID type assignment.
- Norwegian console and X layouts are working.
- DockChannel UART uses measured AIC input 816; the ADT-derived 360 value was
  wrong.
- Both HID interfaces register evdev nodes once the correct kernel is booted:
  `input0: Apple DockChannel Multi-touch` and `input1: Apple DockChannel
  Keyboard`. The trackpad gap is therefore event delivery, not enumeration.
- `hid-generic … device has no listeners, quitting` right after
  `Initializing comm interface <4- "actuator">` is **benign** — that is the
  actuator interface, a non-input HID interface with nothing to claim it. Do not
  read it as a keyboard failure.
- A shell spawned by `/init` with inherited stdin has **no controlling
  terminal**: busybox prints `can't access tty: job control turned off` and
  ignores every keypress. Rescue shells must run under `setsid -c` on a real VT.
  Also drop the console loglevel first — the `apple-pmgr-pwrstate sync_state()`
  stream scrolls the prompt away for seconds and makes a working shell look
  dead.

### CPU

- All 14 cores enter the kernel.
- A five-core RAM-root desktop schedules work on every online core.
- The old “fails at maxcpus >= 6” claim is superseded. A dependency-free
  BusyBox copy-on-write workload faults at `maxcpus=2` while the same run is
  clean at one core.
- The uninstrumented control produced two kernel-mode page faults in four runs.
  Argument-validation work before `copy_page()` suppressed the fault in four
  runs without finding an invalid argument.
- The ticket 207 bisect refuted the ordering hypothesis: `smp_mb()` alone and a
  semantically irrelevant volatile read of the destination each suppressed the
  fault equally. Any small perturbation before `copy_page()` hides it, so the
  race is not located in `copy_highpage`. The kernel-mode fault on a valid
  linear-map address points at page lifetime/refcount or TLB-invalidation
  completion; an upstream-quality report is the next step.
- **The failure is fail-stop, not silent corruption (round 18, 2026-08-03).**
  With the fork-heavy reproducer running in the background and a fault firing
  that killed it, twelve consecutive 64 KiB copy-and-compare verifications in
  the surviving process were byte-identical (`SAME=12, DIFFER=0`, loop
  completed). That matches the fault path by construction —
  `die_kernel_fault` → `arm64_force_sig_fault` → `make_task_dead`. So
  `maxcpus>1` costs availability, not data, and storage written during earlier
  multi-core sessions is not suspect. Bounded honestly: it does not prove that a
  process *hit* by the fault writes nothing bad before dying, nor that a fault
  during page-cache writeback cannot reach storage.
  Method note — the test must be cheap enough to survive itself: 64 KiB units
  (not 2 MiB), generate the pattern once, and one `cmp -s` instead of two
  `md5sum` calls. Heavier versions killed the shell before emitting any verdict,
  which is why the question stayed open for a dozen rounds.
- Fresh-boot baselines and at least four repetitions are required: the first
  run is the most sensitive, and a single clean run is weak evidence.
- cpufreq works after widening the driver’s `frequency * 1000` calculation;
  P cores reach 4.512 GHz.
- `idle=nop` remains a bring-up workaround, not a power-management solution.

### SMC

- Correcting the SMC SRAM region enabled battery, AC, charger, and temperature
  telemetry.
- PCIe endpoint power uses the maintainer-approved upstream GPIO path for
  `gP13` and `gP19`.
- No other SMC key is authorized without a recorded exception.

### PCIe, WiFi, and Bluetooth

- The T6040 PHY reset bit is bit 4, not the older bit 7.
- Endpoint power, not a missing PLL sequence, was the remaining link blocker.
- BCM4388 requires antenna SKU `X3`.
- The rev-6 device uses c2 firmware content under the c0 filenames expected by
  brcmfmac.
- Apple firmware reports BSS-info version 116; the Wallace patch accepts it.
- WiFi association, DHCP, routed traffic, and Bluetooth `hci0` are proven.
- GL9755 enumerates on PCIe port 1.

### SD

- Built-in MMC, SDHCI-PCI, and exFAT support expose the GL9755 card as
  `mmc0` and `/dev/mmcblk0p1`.
- File write, sync, unmount, reboot, remount, and hash persistence are proven.
- The persistent-root prototype stores a 6 GiB ext4 loop image on the existing
  exFAT partition without repartitioning or formatting it.
- At `maxcpus=1`, the loop root reaches ttydc0 and OpenRC and retains writes.
- Panic testing left exFAT and ext4 unclean. Ticket 215 owns repair; ticket 216
  owns the staged PID-1 shutdown pivot and post-shutdown clean checks.
- Repair is a real `fsck.exfat`, never clearing exFAT `VolumeFlags` bit 1: an
  unclean shutdown mid-write can leave genuine metadata inconsistency, and
  masking the flag would mount a container already known to be suspect
  (CJ's decision, 2026-08-03). The initramfs therefore carries a **statically
  linked** `sbin/fsck.exfat` — it has no libc and no dynamic loader, so a
  dynamic binary would pull glibc plus `ld-linux` into the boot path. Built from
  Debian `exfatprogs 1.2.0-1+deb12u1` source in the arm64 kbuild container with
  `make LDFLAGS=-all-static` (libtool ignores a plain `-static` in `LDFLAGS`,
  and a PIE default silently defeats it), stripped, and hash-pinned in
  `scripts/t6040-build-sdroot-initramfs.sh`.
- The dirty gate stays unconditional *after* any repair: clean at that point or
  no read-write mount.
- **PCIe gates in `/init` must wait, not sample.** `/init` has been observed
  running at 0.20 s, long before `apple-pcie` brings up port 2 or `sdhci-pci`
  binds. The GL9755 presence and driver checks originally sampled sysfs once
  while only the block device got a timeout, so a slow probe was reported as
  "absent". Both now wait up to 25 s and log how long they took, which
  distinguishes a real absence from "not yet".

### Internal NVMe

- Raw m1n1 initializes T6040 ANS without resident SPTM and sustains reads over
  several CQ wraps.
- Linux’s T8132-style driver initializes ANS, enumerates namespaces, reads the
  GPT, and briefly mounts the exFAT partition.
- Linux firmware then asserts at the first I/O completion-queue wrap.
- The failure is Linux-specific. Simple ring depth, batching, eager CQ
  acknowledgement, one outstanding I/O, CQ IRQ enable, non-zero tag/TCB slot,
  phase logic, and the “wrong submission doorbell window” explanation have
  been tested or refuted.
- Hard-IRQ completion, live admin traffic, and other remaining execution-order
  differences are candidates, not established causes.
- Linux NVMe writes remain blocked.

### Trackpad

- The exact paired HIDF blob is available and its narrow volatile-use
  exception was exercised.
- The upload command returned success at the protocol layer.
- The post-upload `0x40` rejection is **solved**: `0x40` is the MTP
  coprocessor's interface *power request*, not a reset, and J614s firmware
  implements only the nine-byte version-2 two-phase form. The four-byte v1
  form failed its length check with `kIOReturnBadArgument` before any field
  was read (static decode, 2026-08-04).
- `patches/t6040-dockchannel-hid-reset-contract.patch` sends the v2 pair.
  Proven live on 2026-08-04 (ticket 230): all four `0x40` messages returned
  0, the coprocessor consumed the CBOR image (`New AFE[0] cbor image
  received`, which also proves DMA reachability through `mtp_dart`), and the
  pipeline raised `Touch interface ready` / `Touch MT ready` 260 ms after the
  first `open()`. A second open does not re-upload and stays healthy.
- The earlier “firmware upload crashes the machine” attribution is withdrawn.
- The finger test PASSED 2026-08-19 (touch + haptic click); ticket 230 closed.
  Remaining is daily-image integration (ticket 301, see NEXT_STEPS §5).

### USB and Type-C

- Linux DWC3 device mode configures and enumerates gadget functions.
- The tested RNDIS/ECM/NCM/ACM shapes did not produce a usable network
  interface on the current macOS host.
- Right HPM2 WAKEUP and SSPS-to-S0 are proven.
- A reversible role/VBUS/interrupt/PHY sequence is not known. R3 remains
  no-go; no USB-host device has been proven through that path.
- The offline SN201202x transport port is deliberately uncalled and is not a
  VBUS implementation.
- **The CD321x/I2C plan is refuted** (231, 2026-08-04): the captured ADT
  shows four PD controllers, all SPMI `usbc,sn201202x,spmi`; the in-tree
  `tipd` driver is I2C-only and nothing in the tree matches `sn201202x`. Any
  VBUS implementation goes through SPMI and therefore through an offline R3
  design plus CJ sign-off, per `SPMI_SAFETY.md`.
- The 2026-08-04 right-port enumeration run (108, S128 stick present) failed
  **before** the VBUS question: `dwc3-apple 392280000.usb: error -EINVAL:
  failed to initialize core` with the Jul-29 `usb2-native-right` image pair —
  a regression relative to the 2026-07-21 smoke, which reached xHCI root
  hubs. Root cause (2026-08-04): v1 of the PHY slice defaulted to
  `PHY_MODE_INVALID`, and no dwc3 path can deliver `set_mode` before
  `power_on` — the Jul-21 smoke worked only because its DTB had no `phys=`
  at all. Fixed in v2 (probe defaults to host; independently reviewed).
- The v2 re-run artifact was built and reproduced (303, 2026-08-18;
  `buildB` `80248306…`), binary-reviewed PASS (2026-08-19), and **run: the
  v2 fix is verified live** — eUSB2 host sequence complete, dwc3 clean,
  right xHCI root hubs up and persistent, 0 DART faults, NVMe/SPMI provably
  absent from the kernel. No child device: VBUS remains the sole gap to
  enumeration (or the stick left the port; unresolved until CJ looks).
- The tps6598x SPMI transport (231) passed exact-source review 2026-08-18; a
  draft hpm2-only connector DT exists. CJ signed off the SPMI envelope
  2026-08-19 (see `SPMI_SAFETY.md` Entry 1); the attended PD/VBUS run is staged
  (305, see NEXT_STEPS §6).

## Corrections and dead ends

Do not repeat these without new evidence:

- **A latched SMC power rail as the cause of a missing SD reader (2026-08-03).**
  The reader, the card, and the rail were all fine. `$OUT/Image` was the Jul 24
  build, containing *zero* occurrences of `pcie-apple` and `macsmc` — no PCIe
  driver and no SMC driver at all. That single fact manufactured every symptom:
  empty `/sys/bus/pci/devices`, `GL9755 0000:02:00.0 is absent`, no `mmcblk0`,
  no `wlan0`, no `/dev/input` and therefore a dead keyboard, and a silent
  dockchannel console. Acting on the wrong theory cost two needless physical
  interventions (an SD reseat and a hard power cycle) plus most of an evening.
  The tell that was walked past: a sub-second failure timestamp
  (`[0.205907]`) means a startup race or a wrong artifact, never a power rail —
  at 0.2 s nothing has enumerated yet.
- **Silent memory corruption from the SMP page-copy bug.** Round 18 refuted it:
  with a fault firing and killing a concurrent process, twelve consecutive
  64 KiB copy-and-compare verifications were byte-identical. The bug is
  fail-stop. Do not describe `maxcpus>1` as a data-integrity hazard.
- **`console=ttydc0` as the cause of a dead keyboard.** The flag is fine and the
  known-good desktop recipe includes it; what matters is *ordering*. All
  `console=` entries receive printk, but the **last** becomes `/dev/console`,
  which is what init's shell opens for stdin. Put `console=tty0` last so the
  panel keeps the shell; keep `ttydc0` earlier so serial still logs.
- DockChannel IRQ 360. Use measured input 816.
- PCIe op-115 as a missing PLL-lock sequence. The load-bearing fixes were the
  reset bit and endpoint power.
- A fixed SMP failure threshold at six CPUs. The current evidence indicates a
  broader, non-monotonic MM/COW problem.
- A missing barrier in `copy_highpage` as the two-core CoW fault. `smp_mb()`
  and a semantically irrelevant read suppress it equally; suppression by
  perturbation is not evidence of an ordering bug, and neither variant may
  ship as a fix.
- Loss of ttydc0 output as proof of a hung kernel. Several apparent hangs were
  host-reader failures.
- The NVMe submission-doorbell “wrong window” fix. The suspect Linux window
  already submits working commands; moving it caused a separate failure.
- Non-zero NVMe tag/TCB slot as the CQ-wrap trigger.
- SPTM as an absolute requirement for direct T6040 NVMe access.
- USB gadget networking failure as absence of macOS CDC drivers. The drivers
  exist; the tested descriptor/composite shapes did not bind usefully.
- SBU serial, blind MMIO sweeps, generic HPM iteration, SID scans, or guessed
  ATC register buckets.
- A G14 GPU configuration relabeled as T6040/G16.

## Milestone chronology

| Date | Result |
|---|---|
| 2026-07-10 | Stable proxy, CPU topology, and first Linux handoff |
| 2026-07-11 to 07-14 | Keyboard, DockChannel, PMGR, SMC/NVMe/PCIe static foundations |
| 2026-07-24 | Self-contained Alpine object and two-way DockChannel workflow |
| 2026-07-25 | First untethered enrolled Alpine and Ubuntu boots |
| 2026-07-26 | Xorg/dwm with the internal keyboard |
| 2026-07-28 | SMC telemetry and Linux USB device mode |
| 2026-07-29 | PCIe, WiFi, Bluetooth, and the five-core desktop |
| 2026-07-30 to 07-31 | cpufreq and Linux NVMe filesystem I/O bounded to the first CQ-wrap assert |
| 2026-08-02 | SD read/write persistence and corrected trackpad reset attribution |
| 2026-08-03 | One-core SD root reaches ttydc0/OpenRC; controlled two-core page-copy reproducer established; the barrier bisect refuted the ordering hypothesis, pointing at page lifetime or TLB invalidation |
| 2026-08-04 | SD-root daily-driver baseline (Xorg/i3, WiFi, Norwegian layouts, self-healing card); **trackpad transport fixed live** — the v2 interface power request is accepted, firmware consumed, `Touch MT ready` (230); right-port USB regressed to a dwc3 core-init `-EINVAL` (108) and the PD controllers were identified as driverless SPMI `sn201202x` (231) |
| 2026-08-18 | USB lane fully staged offline: dwc3 `-EINVAL` root cause (v1 phy-mode ordering) fixed and reviewed; the v2phy re-run image built and byte-reproduced fresh-vs-fresh (`80248306…`, 303) — the two-build protocol caught a real one-byte stale object in a reused dir; tps6598x SPMI transport passed exact-source review; draft hpm2-only PD connector DT compiled; everything now waits on binary review, CJ's SPMI-envelope sign-off, and rig time |

Detailed transcripts, hashes, retractions, and per-experiment stop conditions
remain in dated files under `evidence/` and in Git history.
