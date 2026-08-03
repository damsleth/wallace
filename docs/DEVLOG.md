# T6040 / J614s development log and operating notes

Current as of 2026-08-03. This file keeps durable operating knowledge,
milestones, corrections, and dead ends. Exact experiment evidence lives in
`evidence/`; current work lives in [NEXT_STEPS.md](NEXT_STEPS.md).

## Current state

| Area | State |
|---|---|
| Boot | Enrolled, untethered Linux boot works |
| Display | simpledrm/fbcon and Xorg with i3 or dwm |
| Input | Keyboard works; trackpad reset contract unresolved |
| CPU | Five-core RAM-root desktop works; a controlled two-core page-copy reproducer faults |
| SMC | Battery, AC, charger, and temperature telemetry |
| PCIe | Root complex, WiFi, Bluetooth, and SD reader work |
| Storage | One-core SD root reaches ttydc0/OpenRC; repair and clean-shutdown validation pending |
| NVMe | m1n1 reads work; Linux loses ANS at its first I/O CQ wrap |
| USB | Device mode works; host role/VBUS does not |

## Operating the rig

### Lease first

Only the lease holder runs a rig script, and only for an approved, ready
ticket. Release `wedged` if recovery is incomplete or uncertain. The canonical
protocol and commands are in [COORDINATION.md](COORDINATION.md).

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
- Do not mount the SD root read/write before ticket 215 passes.

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
- The following `CMD_RESET_INTERFACE(0)` returned
  `kIOReturnBadArgument`.
- The earlier “firmware upload crashes the machine” attribution is withdrawn.
  Motion is still unavailable.

### USB and Type-C

- Linux DWC3 device mode configures and enumerates gadget functions.
- The tested RNDIS/ECM/NCM/ACM shapes did not produce a usable network
  interface on the current macOS host.
- Right HPM2 WAKEUP and SSPS-to-S0 are proven.
- A reversible role/VBUS/interrupt/PHY sequence is not known. R3 remains
  no-go; no USB-host device has been proven through that path.
- The offline SN201202x transport port is deliberately uncalled and is not a
  VBUS implementation.

## Corrections and dead ends

Do not repeat these without new evidence:

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

Detailed transcripts, hashes, retractions, and per-experiment stop conditions
remain in dated files under `evidence/` and in Git history.
