# T6040 / J614s Linux roadmap

Current as of 2026-08-19. This is the stage map; tickets contain the executable
work and [NEXT_STEPS.md](NEXT_STEPS.md) contains the current order.

## Project state

| Stage | State | Remaining boundary |
|---|---|---|
| A. Stable proxy and recovery | Complete | Maintain the lease and DebugUSB discipline |
| B. m1n1 Linux boot | Raw-object path complete; removable stage 2 active | SD-capable U-Boot, proxy fallback, reviewed tethered first light |
| C. Kernel DT and core boot | Functional | MM/SMP stability, cpuidle, upstreaming |
| D. Local usable machine | Partial | Clean SD-root shutdown, panel backlight, USB-host VBUS (trackpad done 2026-08-19) |
| E. WiFi and Bluetooth | Functional | Integration and upstreaming |
| F. GPU acceleration | Blocked on a real T6040/G16 stack | Maintainer-endorsed kernel, firmware ABI, m1n1, and Mesa support |
| G. Power and peripherals | Partial | Audio, camera, suspend, cpuidle, lid/power integration |
| H. Persistent distro | Partial | One-core SD root works; a static `fsck.exfat` now ships in the initramfs to repair the dirty fixture, and clean-shutdown validation is pending |

## A. Proxy and recovery

Complete and stable infrastructure (DebugUSB/KIS proxy, remote reboot, tethered
chainload, `rig-lease.sh` serialization). The recovery bar is a quiescent
`Running proxy`, not merely a responsive USB device. Not an active target.

## B. Boot chain

Complete: m1n1 boots Linux and provides the board DT; a self-contained raw
object (m1n1 + kernel + DTB + initramfs + bootargs) cold-boots enrolled without
a tether; builder/verifier enforce 16 KiB total size; a dual-mode loader keeps a
short DebugUSB window before normal boot.

The active daily-driver target is now a stable removable stage-2 chain:

```text
iBoot -> enrolled, 16-KiB-aligned m1n1
          |-> short DTR window -> Running proxy...
          `-> embedded U-Boot
                |-> valid SD daily bundle -> Linux
                |-> valid USB daily bundle -> Linux (later, after VBUS)
                `-> no valid media -> one-shot RAM reason + warm reboot
                                      -> enrolled m1n1 -> Running proxy...
```

SD is first because the GL9755 and Linux SD root are proven. The daily bundle
is Image + J614s DTB + initramfs + bootargs/manifest, not another enrolled m1n1
object. The current SD64 outer filesystem is exFAT, which U-Boot does not read;
a separately identified card or explicitly authorized small FAT32 boot
partition is required before a physical-media write. No such write is implied
by this roadmap.

The early DTR window remains a permanent recovery edge. U-Boot does not return
directly to m1n1; no-media fallback uses a versioned, one-shot cookie in
reserved normal RAM and the permitted warm reboot so iBoot re-enters the
enrolled m1n1 normally. PCIe/DART/GL9755 initialization must have exactly one
owner. Ticket 3011 resolved that handoff: m1n1 powers the SD endpoint through
the exact approved `gP19`, initializes the common PHY/link once, and U-Boot may
only attach to an already-up link while owning DART1/PCI/MMC above it.

Tickets 3010-3020 own the architecture, ownership audit, proxy cookie, SD
U-Boot target, bundle tooling, composed-object review, read-only tethered first
light, later USB extension, physical-media preflight, and the exact Linux
handoff bundle. The full design and failure edges are recorded in
[the removable stage-2 architecture](../evidence/2026-08-19-t6040-removable-stage2-architecture.md).

## C. Kernel and board description

Working: the full T6040 board (CPU topology, AIC, PMGR, watchdog, framebuffer,
DockChannel UART/HID, SMC, PCIe, SDHCI, WiFi, BT, cpufreq, experimental NVMe) on
the Wallace branch; all 14 CPUs enter the kernel; five-core RAM-root desktop;
cpufreq 4.512 GHz on the P cluster.

Open:

- characterise the two-core page-copy fault and report it upstream (209/217);
  207 refuted the ordering hypothesis, and perturbations that merely suppress the
  symptom are not fixes;
- prove stable 14-core userspace;
- add a safe cpuidle/retention contract;
- keep generated DTs and the upstream-shaped patch series synchronized;
- upstream the narrow, proven changes.

## D. Local usable machine

Working: internal panel (simpledrm/fbcon), Xorg i3/dwm, internal keyboard
(Norwegian), DockChannel shell + watchdog, SMC telemetry, GL9755 SD
read/write persistence, and the **trackpad** (touch + haptic click, 230).

Open:

- repair and validate clean SD-root shutdown;
- complete SSH and graphical service integration;
- enable panel backlight control (keyboard backlight already works);
- bring up USB host: the USB2 data path is proven (108); VBUS remains, sourced by
  the reviewed, CJ-signed-off SPMI PD driver (231) under a reversible Type-C
  contract, attended run staged (305).

The SD path replaces USB root as the immediate persistence route.

## E. WiFi and Bluetooth

Functional: PCIe links train with the correct T6040 PHY reset bit and endpoint
power; BCM4388 WiFi associates/DHCP/routes and BT exposes a working `hci0`;
paired firmware mapping and BSS-info v116 support recorded.

Remaining work is cleanup, regression coverage, and upstream review. Do not
reopen the old op-115 PLL theory; endpoint power and the reset bit were the
load-bearing fixes.

## F. GPU

No safe T6040/G16 live candidate exists. The first candidate must explicitly
support:

- T6040/G16 identity and configuration;
- the matching macOS 26.x firmware ABI;
- T6040 GPU DT/UAT reservations in m1n1;
- a Mesa G16 path selected through the kernel UAPI.

Do not adapt G14 tables by analogy. The staged test sequence remains in
[the GPU upstream smoke playbook](playbooks/GPU_UPSTREAM_SMOKE.md).

## G. Power and remaining peripherals

Partial: SMC telemetry, cpufreq, watchdog, and remote reboot work. Open: cpuidle
and suspend, panel backlight, audio, camera/ISP, lid/power-button integration,
and a thermal/performance policy for sustained daily use. The current `idle=nop`
baseline is for bring-up, not a finished power model.

## H. Persistent distro

Current architecture: enrolled raw m1n1 stage → small switch-root initramfs →
exFAT SD partition holding `wallace-root.img` → ext4 loop image as the Alpine
root.

Target architecture: the stable enrolled m1n1 delegates normal boot to the
removable stage-2 chain in §B. The Linux bundle may live on a small FAT32 boot
partition while the existing exFAT + ext4-loop root layout remains unchanged.
This separates frequent kernel/DT/initramfs updates from 1TR enrollment.

Verified: SD read/write/sync/persistence, loop mount + `switch_root`, and
ttydc0/OpenRC from the SD root at `maxcpus=1` with writes persisting across
reboot.

Required for completion: repair the currently dirty exFAT and ext4 filesystems;
validate the shutdown pivot and post-shutdown clean checks; reliable SSH;
WiFi/Bluetooth services; Xorg/i3 startup; repeated cold-boot validation.

Internal NVMe is a later replacement candidate — Linux reaches real filesystem
I/O but still loses the controller at the first I/O CQ wrap.

## Completion criteria

The project reaches a practical mainline daily-driver milestone when an
enrolled boot reliably reaches the persistent SD root with a working panel,
keyboard, trackpad, network, power telemetry, stable multi-core execution, and
clean shutdown. GPU acceleration, audio, camera, and suspend may land
incrementally, but their absence must remain explicit.
