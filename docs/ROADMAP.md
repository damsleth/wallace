# T6040 / J614s Linux roadmap

Current as of 2026-08-19. This is the stage map; tickets contain the executable
work and [NEXT_STEPS.md](NEXT_STEPS.md) contains the current order.

## Project state

| Stage | State | Remaining boundary |
|---|---|---|
| A. Stable proxy and recovery | Complete | Maintain the lease and DebugUSB discipline |
| B. m1n1 Linux boot | Complete for the current raw-object path | Upstream cleanup and optional standard stage 2 |
| C. Kernel DT and core boot | Functional | MM/SMP stability, cpuidle, upstreaming |
| D. Local usable machine | Partial | Clean SD-root shutdown, panel backlight, USB-host VBUS (trackpad done 2026-08-19) |
| E. WiFi and Bluetooth | Functional | Integration and upstreaming |
| F. GPU acceleration | Blocked on a real T6040/G16 stack | Maintainer-endorsed kernel, firmware ABI, m1n1, and Mesa support |
| G. Power and peripherals | Partial | Audio, camera, suspend, cpuidle, lid/power integration |
| H. Persistent distro | Partial | One-core SD root works; a static `fsck.exfat` now ships in the initramfs to repair the dirty fixture, and clean-shutdown validation is pending |

## A. Proxy and recovery

Complete:

- DebugUSB/KIS reaches a stable m1n1 proxy.
- Remote reboot and tethered chainload are routine.
- All rig access is serialized through `scripts/rig-lease.sh`.
- The recovery bar is a quiescent `Running proxy`, not merely a responsive
  USB device.

Keep this stable; it is infrastructure, not an active hardware target.

## B. Boot chain

Complete:

- m1n1 boots Linux on T6040 and provides the board DT.
- A self-contained raw object carries m1n1, kernel, DTB, initramfs, and
  bootargs.
- An enrolled object cold-boots without a tether.
- The builder and verifier enforce the 16 KiB total-size requirement.
- A dual-mode loader preserves a short DebugUSB window before normal boot.

Optional follow-on:

- design a fail-closed stage-2 loader so the enrolled stage changes rarely;
- compare internal NVMe with SD storage;
- use a raw partition or a supported filesystem. U-Boot does not read exFAT.

This is an iteration improvement, not a prerequisite for the current system.

## C. Kernel and board description

Working:

- T6040 CPU topology, AIC, PMGR, watchdog, simple framebuffer, DockChannel
  UART/HID, SMC, PCIe, SDHCI, WiFi, Bluetooth, cpufreq, and experimental NVMe
  nodes exist on the Wallace branch.
- All 14 CPUs enter the kernel.
- A five-core RAM-root desktop schedules work on all five CPUs.
- cpufreq reaches 4.512 GHz on the P cluster.

Open:

- characterise the two-core page-copy fault and report it upstream (tickets
  209/217); ticket 207 refuted the ordering hypothesis, and perturbations that
  merely suppress the symptom are not fixes;
- prove stable 14-core userspace;
- add a safe cpuidle/retention contract;
- keep generated DTs and upstream-shaped patch series synchronized;
- upstream the narrow, proven changes.

## D. Local usable machine

Working:

- internal panel through simpledrm/fbcon;
- Xorg with i3 or dwm;
- internal keyboard with Norwegian layout;
- DockChannel shell and watchdog;
- battery, AC, charger, and temperature telemetry;
- GL9755 SD read/write persistence.

Open:

- repair and validate clean SD-root shutdown;
- complete SSH and graphical service integration;
- enable panel backlight control; keyboard backlight already works;
- bring up USB host: the USB2 data path is proven (108); VBUS remains, and the
  reviewed, CJ-signed-off SPMI PD driver (231) sources it under a reversible
  Type-C contract — attended run staged (305).

Done:

- **trackpad (touch + haptic click), 2026-08-19** (230): a real finger produced
  37 950 events on `/dev/input/event0` and force-click haptics fire. Daily-image
  integration is ticket 301.

The SD path replaces USB root as the immediate persistence route.

## E. WiFi and Bluetooth

Functional:

- PCIe links train with the correct T6040 PHY reset bit and endpoint power;
- BCM4388 WiFi scans, associates, receives DHCP, and routes traffic;
- BCM4388 Bluetooth exposes a working `hci0`;
- the paired firmware mapping and BSS-info v116 support are recorded.

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

Partial:

- SMC telemetry works;
- cpufreq works;
- watchdog and remote reboot paths exist.

Open:

- cpuidle and suspend;
- panel backlight;
- audio;
- camera/ISP;
- lid and power-button integration;
- thermal and performance policy suitable for sustained daily use.

The current `idle=nop` baseline is for bring-up, not a finished power model.

## H. Persistent distro

Current architecture:

1. enrolled raw m1n1 stage;
2. small switch-root initramfs;
3. exFAT SD partition containing `wallace-root.img`;
4. ext4 loop image as the Alpine root.

Verified:

- SD read, write, sync, unmount, reboot, and hash persistence;
- loop mount and `switch_root`;
- ttydc0 and OpenRC work from the SD root at `maxcpus=1`;
- writes persist across reboot.

Required for completion:

- repair the currently dirty exFAT and ext4 filesystems;
- validate the shutdown pivot and post-shutdown clean checks;
- reliable SSH;
- WiFi/Bluetooth services;
- Xorg/i3 startup;
- clean shutdown and filesystem checks;
- repeated cold-boot validation.

Internal NVMe is a later replacement candidate. Linux reaches real filesystem
I/O but still loses the controller at the first I/O CQ wrap.

## Completion criteria

The project reaches a practical mainline daily-driver milestone when an
enrolled boot reliably reaches the persistent SD root with a working panel,
keyboard, trackpad, network, power telemetry, stable multi-core execution, and
clean shutdown. GPU acceleration, audio, camera, and suspend may land
incrementally, but their absence must remain explicit.
