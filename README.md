# Project Wallace

Project Wallace is bringing Linux to the 14-inch M4 Pro MacBook Pro: Apple
Mac16,8 / J614s, built around the T6040 “Brava Chop” SoC. The project
tracks the board description, kernel and m1n1 changes, build tooling, experiments,
and evidence needed to turn first-boot support into a reliable upstream-quality
Linux system.

This is experimental bring-up work, not a ready-to-install distribution. There
is no public installer image yet, and the machine is not ready to replace macOS
as a dependable daily driver.

## Status, reviewed 2026-10-30

Linux boots both tethered and untethered. The current baseline is a
**standalone Alpine system on the internal SSD**: an enrolled m1n1 object boots
straight into a persistent root on the internal NVMe (`linux` exFAT partition),
with Xorg and i3 on the internal panel at 2x HiDPI scaling, the internal
keyboard with the Norwegian layout, the **trackpad (multi-touch and haptic
click)**, WiFi joining automatically, Bluetooth including **BLE mice and
keyboards**, SMC telemetry and cpufreq. Development now happens on the machine
itself. The kernel it runs (ticket 5019) adds ftrace, kprobes, dynamic debug and
a ramoops crash log. The SSD rejects NVMe Flush, so it runs write-through and
needs clean shutdowns. A five-core RAM-root desktop has run successfully; the
daily system uses one core because a multi-core kernel fault remains the largest
reliability blocker. Its leading cause is now a firmware-locked memory window
that Linux must reserve (ticket 5015).

Two milestones landed 2026-08-19: the **trackpad now works end to end** — a
real finger produced 37 950 events and force-click haptics fire (ticket 230) —
and the **USB2 host data path came up** (dwc3 probes, the right-port xHCI root
hubs are healthy), leaving VBUS as the only remaining gap for external storage.
A reviewed, signed-off Type-C PD driver for the SoC's SPMI power controllers is
staged for the VBUS run (ticket 231/305).

That race is now characterised as **fail-stop**: it kills processes rather than
returning wrong data. With a fault firing and killing a concurrent process,
twelve consecutive copy-and-compare verifications came back byte-identical. Those observations establish a fail-stop outcome for that test. They do not
prove what happens to a faulting process or page-cache writeback; the daily
profile stays at `maxcpus=1`.

The project has therefore moved beyond “can Linux boot?” The work now is making
the existing hardware support stable, maintainable, and suitable for upstream
review.

## Hardware support

| Component | What works | What remains |
|---|---|---|
| Boot | A self-contained, enrolled m1n1 object cold-boots Linux without a host-supplied payload | An SD-first removable U-Boot stage 2 is active offline work (3010–3020), with a permanent proxy recovery path |
| CPU and cpufreq | All 14 cores enter the kernel; a five-core RAM-root desktop and frequency scaling are proven. The observed multi-core failure is fail-stop; broader writeback safety remains unproven | Multi-core page-copy workloads can fault in the kernel. A minimal reproducer exists; the simple missing-barrier theory has been refuted, leaving page lifetime/refcount or TLB invalidation as leading areas to investigate |
| Display | simpledrm/fbcon and Xorg with i3 or dwm work on the internal panel | No GPU acceleration or panel-backlight control |
| Input | The internal keyboard works in X (Norwegian layout, ⌘ as the i3 modifier) and the keyboard backlight works. **The trackpad works:** a real finger produced 37 950 events on `/dev/input/event0` in a 60 s window, and **force-click haptics fire** (Taptic actuator). The fix was the post-upload MTP interface power request — J614s accepts only the 9-byte v2 form (ticket 230, 2026-08-19). BLE mice and keyboards work through UHID (5019; MX Ergo S verified 2026-10-30) | Fold the patch and firmware blob into the daily image (301); gestures/tuning are userspace config |
| SMC and power | Battery, AC, charger, and temperature telemetry work | cpuidle, suspend, lid/power integration, and production power policy remain incomplete |
| PCIe | The T6040 root complex, link training, and approved endpoint-power paths work | Upstream cleanup and broader regression coverage |
| WiFi and Bluetooth | BCM4388 WiFi associates, receives DHCP, and routes traffic (verified 2026-08-04 on an open 5 GHz network, with `ping` and `curl` working); Bluetooth exposes a working `hci0` | Only one `wpa_supplicant` may run or the radio is starved; `regulatory.db` is missing so the domain stays `country 00` |
| SD storage | Read/write persistence demonstrated. The GL9755 reader enumerates as `mmc0`, the repair image carries static `fsck.exfat`, and the ext4 loop root has mounted read-write. A 64 KiB random file hashed identically across four reboots | Repair the dirty fixture (215), validate clean shutdown (216), and repeat cold boots without the tether |
| Persistent root | The daily root is now an ext4 loop image on the internal NVMe (5005/5008), booted standalone; the earlier SD-card root: at `maxcpus=1`, an ext4 loop image on the SD card boots unattended to Xorg and i3, associates with WiFi, and retains writes across reboots. `/init` self-heals the card's helper scripts, keymap, timezone, cursor theme and WiFi config from the image, so the card can no longer drift behind the repo | Clean shutdown and repeated cold-boot validation |
| Internal NVMe | Linux reads and writes work at `maxcpus=1`: 16,384 direct reads through about 256 completion-queue wraps (6001), 1 GiB written at about 410 MB/s with a matching read-back hash (211), and the daily root lives on it (5005/5008) | ANS2 rejects NVMe Flush, so the SSD runs write-through and the newest writes survive only a clean controller shutdown; a Flush encoding without a DMA direction is next (5023) |
| USB | Device mode works; the **USB2 host data path works** — with the v2 PHY slice, dwc3 probes and the right-port xHCI root hubs come up healthy (ticket 108, 2026-08-19) | **VBUS is the sole gap** for a bus-powered device. A reviewed, CJ-signed-off tps6598x SPMI transport drives the SoC's `sn201202x` PD controllers; the attended VBUS run is staged (231/305). USB3/Thunderbolt (atcphy) is later work |
| GPU | The internal framebuffer provides an unaccelerated desktop | T6040/G16 needs matching kernel, firmware-ABI, m1n1, and Mesa support; G14 tables are not a valid substitute |
| Audio, camera, suspend | Hardware topology and dependencies have been mapped in several areas | No usable audio or camera path; suspend is unsafe without a valid CPU-retention model |

## Roadmap

This table is the milestone view; stage-level boundaries and per-stage detail
live in [docs/ROADMAP.md](docs/ROADMAP.md).

| Milestone | State | Result so far | Next boundary |
|---|---|---|---|
| Boot and recovery foundation | Complete | Stable m1n1 handoff, tethered development, and enrolled untethered Linux boot | Keep the boot artifacts reproducible and prepare upstream-shaped changes |
| Kernel and board foundation | Functional | CPU topology, interrupt controller, PMGR, watchdog, framebuffer, DockChannel, SMC, PCIe, SDHCI, WiFi, Bluetooth, and cpufreq are integrated | Resolve the multi-core memory race, add cpuidle, and upstream the proven pieces |
| Local unaccelerated desktop | Functional | Internal panel, keyboard, keyboard backlight, **trackpad (touch + haptics)**, and Xorg/i3 work, with 2x HiDPI scaling, the Norwegian layout and a usable cursor | Panel backlight, accelerated graphics |
| Connectivity | Functional | WiFi and Bluetooth work over the internal PCIe endpoint; the USB2 host data path is up | VBUS/Type-C for external USB storage (PD driver signed off, run staged), then upstreaming |
| Persistent Linux system | Functional | SD storage is persistent and verified across four reboots; a one-core Alpine root boots to a graphical desktop with WiFi | Prove clean shutdown, then validate across repeated cold boots |
| Stable multi-core userspace | Active blocker | Five-core RAM-root use is proven, the two-core kernel fault has a small repeatable reproducer, and the failure mode is confirmed fail-stop rather than silently corrupting | Report and isolate the page lifetime/TLB failure; do not treat timing perturbations as a fix |
| Internal NVMe root | Functional | The daily root runs from the internal SSD; Linux reads survive CQ wraps and writes are verified | Make writes durable without a clean shutdown (Flush, 5023) |
| Power and multimedia | Early | SMC telemetry and cpufreq work; audio/camera topology is documented | cpuidle, suspend, panel backlight, audio, camera, lid handling, and thermal policy |
| Practical daily driver | Not yet | Most of the basic platform is visible and several major devices work | Clean persistent boot, stable multi-core execution, trackpad, backlight, and dependable service integration |

## Current priorities

**The current objective is a practical daily driver** (CJ, 2026-08-03): SD, USB,
NVMe, WiFi, Bluetooth and the trackpad all working unambiguously. Upstream
reporting is explicitly deferred until that is reached.

1. **Multi-core (205/5015):** reserve the firmware-locked memory window after the
   ADT and retest SMP with `idle=nop arm64.nowfxt`. The macOS kernel confirms the
   window cannot be unlocked, only avoided.
2. **NVMe durability (5023):** retry Flush with no DMA direction, which is how
   macOS sends it. If it is accepted, the SSD can leave write-through.
3. **On-device development:** finish the ramoops reboot check (5020), then
   kernel switching with kexec (5024/5021) so new kernels need no 1TR visit.
4. **USB host power (305):** the attended right-port VBUS run.
5. Keep the rest open: GPU, panel brightness, audio, camera, suspend, and the
   M4 Pro hardware-tracing plan (6003).

The [October review](evidence/2026-10-24-asahi-dev-review.md) records all
4,008 messages from September 21 through the October 24 snapshot, including
later corrections. [NEXT_STEPS](docs/NEXT_STEPS.md) holds the live priorities
and gates. The 2026-10-30 refresh adds the on-device results: the 5019 kernel, BLE HID, the kexec refusal and the live CTRR layout.

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
| Trackpad | [Finger test PASS — touch + haptic click](evidence/2026-08-19-t6040-trackpad-finger-test-PASS.md) · [v2 power request accepted](evidence/2026-08-04-t6040-trackpad-v2-power-request-accepted.md) |
| USB host | [USB2 data path restored (dwc3 -EINVAL fix)](evidence/2026-08-04-t6040-dwc3-einval-phy-mode-ordering.md) · [SPMI PD transport](evidence/2026-08-04-t6040-tps6598x-spmi-transport.md) |

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
