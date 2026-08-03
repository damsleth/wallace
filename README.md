# Project Wallace

Project Wallace brings mainline Linux to the 14-inch M4 Pro MacBook Pro
(T6040 “Brava Chop”, Mac16,8 / J614s). This repository contains the board
device trees, kernel patches, host tools, build recipes, tickets, and evidence.
The m1n1 and Linux source trees live in sibling repositories.

## Status — 2026-08-03

Linux boots both tethered and untethered. The useful baseline is Alpine with
the internal display and keyboard, PCIe, WiFi, Bluetooth, SMC telemetry, and
five proven CPU cores. The internal SD reader now provides verified persistent
storage. The remaining work is reliability and integration, not first boot.

| Area | Verified state | Current limit |
|---|---|---|
| Boot | Enrolled raw m1n1 object cold-boots Linux without a host payload | Objects must be 16 KiB aligned; standard EFI boot is not required yet |
| Display | simpledrm/fbcon and Xorg with i3 or dwm work on the internal panel | No GPU acceleration or panel-backlight control |
| Keyboard | Internal keyboard and Norwegian layout work | Trackpad motion does not; firmware upload succeeds but the following reset is rejected |
| CPU | All 14 cores enter the kernel; a five-core RAM-root desktop is stable; cpufreq reaches 4.512 GHz on P cores | A broader MM/SMP copy-on-write fault appears under some multi-core workloads; full 14-core userspace is not proven; cpuidle is absent |
| SMC | Battery, AC, charger, and temperature telemetry work | Power-management integration is incomplete |
| PCIe | T6040 PCIe and endpoint power work | Endpoint power is limited to the approved SMC GPIO keys `gP13` and `gP19` |
| WiFi / Bluetooth | BCM4388 associates, gets DHCP, routes traffic, and exposes a working `hci0` | No known bring-up blocker |
| SD | GL9755 enumerates as `mmc0`; exFAT read, write, sync, reboot, and hash persistence are proven | The stricter staged fixture tickets 199/200 remain separate review gates |
| Persistent root | A 6 GiB ext4 loop image on the exFAT SD card mounts and reaches `switch_root`; OpenRC starts | Console, SSH, and graphical services are not yet usable from the SD root |
| Internal NVMe | Raw m1n1 sustains reads across several queue wraps. Linux enumerates namespaces and briefly mounts the exFAT partition | Linux firmware asserts at the first I/O CQ wrap; Linux NVMe writes are not verified |
| USB | The DFU controller works in Linux device mode | macOS does not bind the tested Linux CDC gadget shapes; USB host/VBUS remains unproven |
| Audio / camera / suspend / GPU | Not brought up | These remain later-stage work |

Primary evidence:

- [SD read/write persistence](done/2026-08-02-t6040-SD-CARD-WORKS-persistent-storage.md)
- [SD-root status](done/2026-08-03-t6040-SD-ROOT-persistent-system.md)
- [WiFi and Bluetooth](done/2026-07-29-t6040-WIFI-AND-BLUETOOTH-WORKING.md)
- [Five-core desktop and SMP boundary](done/2026-07-29-t6040-SMP-threshold-maxcpus6-and-5core-shippable.md)
- [NVMe Linux wrap failure](done/2026-07-30-t6040-nvme-linux-wrap-assert-E1-E5.md)
- [NVMe completion-order audit](done/2026-08-03-t6040-nvme-irq-completion-order-audit.md)
- [Trackpad reset result](done/2026-08-02-t6040-trackpad-HIDF-rejected-not-crash.md)

## Current priorities

1. Finish ticket 204: obtain a reliable SD-root console, then restore
   networking and the graphical session one service at a time.
2. Preserve a complete modern ANS crashlog for the Linux NVMe CQ-wrap assert
   (ticket 201), then review the threaded-IRQ discriminator (ticket 203).
3. Reframe and isolate the MM/SMP fault as a general copy-on-write problem,
   rather than an initramfs-size or fixed CPU-count threshold.
4. Resolve the trackpad post-upload interface-reset contract.
5. Keep USB-host/HPM, GPU, audio, camera, and suspend behind their existing
   evidence and safety gates.

The machine is not yet a dependable daily driver: SD-root services, trackpad
motion, multi-core memory stability, accelerated graphics, and backlight
control are still missing.

## Safety and coordination

Two agents share one physical machine. Read
[docs/COORDINATION.md](docs/COORDINATION.md) before any rig work. A rig script
may run only for an approved and independently reviewed ticket while the caller
holds the lease from `scripts/rig-lease.sh`.

Never write PMU, charger, NVRAM, firmware, or unknown SPMI state. The only
additional approved SMC writes are the PCIe endpoint-power GPIO keys
`gP13` and `gP19`. The exact SPMI policy is
[docs/SPMI_SAFETY.md](docs/SPMI_SAFETY.md).

## Repository layout

| Path | Purpose |
|---|---|
| `~/Code/wallace` | this repository: docs, scripts, patches, DTS files, tickets, and results |
| `~/Code/m1n1` | active m1n1 fork |
| `~/Code/m1n1-clean` | curated upstream-shaped m1n1 series |
| `~/Code/linux` | Linux branch `wallace/t6040-bringup` |
| `~/Code/linux-build-out` | container build output and retained artifacts |
| `~/Code/macvdmtool` | DebugUSB entry and remote reboot |
| `~/Code/kisd` | DebugUSB-to-PTY bridge |

## Reading order

1. [AGENTS.md](AGENTS.md): repository map and hard rules.
2. [docs/COORDINATION.md](docs/COORDINATION.md): mandatory shared-rig protocol.
3. [docs/NEXT_STEPS.md](docs/NEXT_STEPS.md): current work only.
4. [docs/RUNBOOK.md](docs/RUNBOOK.md): operational commands.
5. [docs/DEVLOG.md](docs/DEVLOG.md): operating knowledge and chronological history.
6. [docs/ROADMAP.md](docs/ROADMAP.md): stage-level scope.

Actionable work lives in `tickets/`. Completed tickets move to
`tickets/done/`; deprecated or superseded tickets move to
`tickets/archive/`. Detailed experiment records remain in `done/` and are
historical evidence, not current status pages.
