# Project Wallace

Project Wallace is bringing Linux to the 14-inch M4 Pro MacBook Pro: Apple
Mac16,8 / J614s, built around the T6040 “Brava Chop” SoC. The project
tracks the board description, kernel and m1n1 changes, build tooling, experiments,
and evidence needed to turn first-boot support into a reliable upstream-quality
Linux system.

This is experimental bring-up work, not a ready-to-install distribution. There
is no public installer image yet, and the machine is not ready to replace macOS
as a dependable daily driver.

## Status — 2026-08-03

Linux boots both tethered and untethered. The current useful baseline is Alpine
Linux with the internal display and keyboard, Xorg with i3 or dwm, PCIe, WiFi,
Bluetooth, SMC telemetry, cpufreq, and persistent SD storage. A five-core
RAM-root desktop has run successfully; the persistent SD-root system currently
uses one core because a reproducible multi-core kernel memory race remains the
largest reliability blocker.

The project has therefore moved beyond “can Linux boot?” The work now is making
the existing hardware support stable, maintainable, and suitable for upstream
review.

## Hardware support

| Component | What works | What remains |
|---|---|---|
| Boot | A self-contained, enrolled m1n1 object cold-boots Linux without a host-supplied payload | The current raw-object path is project-specific; a conventional stage-2 or EFI-style flow is optional future work |
| CPU and cpufreq | All 14 cores enter the kernel; a five-core RAM-root desktop and frequency scaling are proven | Multi-core page-copy workloads can fault in the kernel. A minimal reproducer exists; the simple missing-barrier theory has been refuted, leaving page lifetime/refcount or TLB invalidation as leading areas to investigate |
| Display | simpledrm/fbcon and Xorg with i3 or dwm work on the internal panel | No GPU acceleration or panel-backlight control |
| Input | The internal keyboard, Norwegian layout, and keyboard backlight work | Trackpad motion does not. Firmware upload succeeds, but the following interface reset is rejected |
| SMC and power | Battery, AC, charger, and temperature telemetry work | cpuidle, suspend, lid/power integration, and production power policy remain incomplete |
| PCIe | The T6040 root complex, link training, and approved endpoint-power paths work | Upstream cleanup and broader regression coverage |
| WiFi and Bluetooth | BCM4388 WiFi associates, receives DHCP, and routes traffic; Bluetooth exposes a working `hci0` | No known bring-up blocker; integration and upstream review remain |
| SD storage | The internal GL9755 reader enumerates as `mmc0`; exFAT read, write, sync, reboot, and hash persistence are verified | Panic testing left the current fixture dirty; automatic repair and clean-shutdown validation are staged before further read/write use |
| Persistent root | At `maxcpus=1`, an ext4 loop image on the SD card reaches ttydc0 and OpenRC and retains writes across reboot | Clean shutdown, repeated cold boots, reliable services, and graphical-session integration still need live validation |
| Internal NVMe | Raw m1n1 reads survive several completion-queue wraps; Linux enumerates namespaces and briefly mounts exFAT | Linux triggers a firmware assert at the first I/O completion-queue wrap; Linux writes are not verified |
| USB | The DFU controller works in Linux device mode | USB host mode, Type-C role handling, and VBUS remain unproven |
| GPU | The internal framebuffer provides an unaccelerated desktop | T6040/G16 needs matching kernel, firmware-ABI, m1n1, and Mesa support; G14 tables are not a valid substitute |
| Audio, camera, suspend | Hardware topology and dependencies have been mapped in several areas | No usable audio or camera path; suspend is unsafe without a valid CPU-retention model |

## Roadmap

This table is the milestone view; stage-level boundaries and per-stage detail
live in [docs/ROADMAP.md](docs/ROADMAP.md).

| Milestone | State | Result so far | Next boundary |
|---|---|---|---|
| Boot and recovery foundation | Complete | Stable m1n1 handoff, tethered development, and enrolled untethered Linux boot | Keep the boot artifacts reproducible and prepare upstream-shaped changes |
| Kernel and board foundation | Functional | CPU topology, interrupt controller, PMGR, watchdog, framebuffer, DockChannel, SMC, PCIe, SDHCI, WiFi, Bluetooth, and cpufreq are integrated | Resolve the multi-core memory race, add cpuidle, and upstream the proven pieces |
| Local unaccelerated desktop | Partial | Internal panel, keyboard, keyboard backlight, and Xorg/i3 or dwm work | Trackpad motion, panel backlight, accelerated graphics, and desktop polish |
| Connectivity | Functional | WiFi and Bluetooth work over the internal PCIe endpoint | Upstreaming and, separately, a safe USB-host/Type-C implementation |
| Persistent Linux system | Partial | SD storage is persistent; a one-core Alpine root reaches console and OpenRC | Repair the fixture, prove clean shutdown, then validate network and desktop services across cold boots |
| Stable multi-core userspace | Active blocker | Five-core RAM-root use is proven, and the two-core kernel fault has a small repeatable reproducer | Report and isolate the page lifetime/TLB failure; do not treat timing perturbations as a fix |
| Internal NVMe root | Experimental | Both m1n1 and Linux reach real media; m1n1 reads are stable across wraps | Explain and fix the Linux first-CQ-wrap firmware assert before any write or root migration |
| Power and multimedia | Early | SMC telemetry and cpufreq work; audio/camera topology is documented | cpuidle, suspend, panel backlight, audio, camera, lid handling, and thermal policy |
| Practical daily driver | Not yet | Most of the basic platform is visible and several major devices work | Clean persistent boot, stable multi-core execution, trackpad, backlight, and dependable service integration |

## Current priorities

1. Turn the reproducible two-core kernel page-copy fault into an upstream-quality
   report and investigate page lifetime/refcount and TLB invalidation. A barrier
   and a plain read both hide the symptom, so neither is a valid fix.
2. Repair and recheck the dirty SD filesystems, then validate the hardened
   SD-root shutdown path and post-shutdown filesystem state.
3. Preserve a complete modern ANS crashlog for the Linux NVMe CQ-wrap assert,
   then test the remaining completion-context hypothesis.
4. Resolve the trackpad's post-firmware-upload interface-reset contract.
5. Continue upstream-oriented work on USB host, GPU, power management, audio,
   and camera support as credible hardware-specific implementations become
   available.

## Where the work lives

This repository is the project's coordination and evidence hub; the code
lives in sibling trees:

| Repository | Content |
|---|---|
| [damsleth/linux](https://github.com/damsleth/linux), branch `wallace/t6040-bringup` | Kernel tree with the T6040 device tree and driver work, based on the Asahi Linux [`asahi-wip`](https://github.com/AsahiLinux/linux) tree |
| [damsleth/m1n1](https://github.com/damsleth/m1n1) | m1n1 bootloader fork used for bring-up experiments and the enrolled boot objects |

In this repository:

- `patches/` — kernel patches the build tooling applies on top of the committed tree
- `dts/` — T6040/J614s device-tree sources and their validation checklist
- `scripts/` — host-side build, boot, verification, and rig-coordination tooling
- `evidence/` — dated experiment write-ups: transcripts, hashes, results, and retractions
- `tickets/` — the working queue (active, done, archived) as JSON records
- `docs/` — operational documentation for the (largely AI-agent) crew running
  the rig: coordination protocol, runbook, safety policies, and roadmap. It is
  deliberately terse and imperative; this README is the human-facing summary.

The project builds directly on the [Asahi Linux](https://asahilinux.org/)
project's kernel, bootloader, and reverse-engineering work, and several Asahi
developers are independently bringing up the same SoC generation.

## Primary evidence

The repository keeps experiment results, exact artifacts, corrections, and
failed hypotheses alongside successful milestones. Useful starting points:

| Area | Evidence |
|---|---|
| Untethered boot | [First enrolled self-contained Linux milestone](evidence/2026-07-25-t6040-B0-MILESTONE.md) |
| CPU | [Five-core desktop and SMP boundary](evidence/2026-07-29-t6040-SMP-threshold-maxcpus6-and-5core-shippable.md) · [Current minimal reproducer and MM/SMP investigation](evidence/2026-08-03-t6040-205-smp-cow-investigation.md) |
| WiFi and Bluetooth | [Working BCM4388 WiFi and Bluetooth](evidence/2026-07-29-t6040-WIFI-AND-BLUETOOTH-WORKING.md) |
| SD storage | [Read/write persistence](evidence/2026-08-02-t6040-SD-CARD-WORKS-persistent-storage.md) · [Persistent-root status and integrity work](evidence/2026-08-03-t6040-SD-ROOT-persistent-system.md) |
| Internal NVMe | [Linux first-CQ-wrap firmware assert](evidence/2026-07-30-t6040-nvme-linux-wrap-assert-E1-E5.md) · [Completion-order audit](evidence/2026-08-03-t6040-nvme-irq-completion-order-audit.md) |
| Trackpad | [Firmware upload and rejected reset result](evidence/2026-08-02-t6040-trackpad-HIDF-rejected-not-crash.md) |

The status above intentionally distinguishes proven behavior from plausible
next steps. A successful one-off boot is not treated as finished hardware
support, and hypotheses that later evidence disproves remain recorded rather
than being rewritten as successes.

## License

The scripts, documentation, and other original content in this repository are
MIT licensed (see [LICENSE](LICENSE)). Patches under `patches/` and
device-tree sources under `dts/` are derived from and destined for the trees
they modify, and carry those trees' licenses: GPL-2.0 for Linux, MIT for
m1n1.
