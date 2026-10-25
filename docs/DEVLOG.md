# T6040 / J614s development log and operating notes

Reviewed through 2026-10-25. This file keeps durable operating knowledge,
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

10. **`deviceinterfaced` re-grabs Debug USB on every re-enumeration
    (2026-10-25).** "Start kisd first" holds only until the next reboot: after
    each recovery or watchdog reboot macOS `deviceinterfaced` can take the
    device again, and CJ's kill loop missed it once (5008 B). The kill needs
    `sudo` and is CJ's to run ([RUNBOOK.md](RUNBOOK.md) §2).
11. **Manual recovery sequence that works (2026-10-25).** After the M4 showed
    `Running proxy` on screen but the link stayed silent (211 r2 verify, three
    reboots), the order that recovered it was: kisd attached, a `cat /tmp/m1n1`
    reader running, *then* `macvdmtool reboot debugusb`; wait for
    `Running proxy` in the reader; stop that reader with the anchored
    `pkill -f '^cat /tmp/m1n1$'`; then `t6040-proxy-alive.py`. This does not
    contradict rule 9: the kill is a recovery step between `Running proxy` and
    the first proxyclient, not a kill of `boot-dcuart.sh`'s own reader during a
    boot. Exact commands in [RUNBOOK.md](RUNBOOK.md) §2. kisd also panicked once
    (`bytes.rs split_to out of bounds`) and had to be restarted.

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
- **Never `rm -rf` a tree with live mounts in a privileged container
  (2026-10-25).** BusyBox `umount` has no `-R`; a harness cleanup that relied
  on it, followed by `rm -rf`, deleted the podman VM's devtmpfs nodes through a
  bind-mounted `/dev` and broke new podman sessions until the VM was restarted.
  Detach each mount separately and refuse to `rm` while anything remains
  mounted ([incident](../evidence/2026-10-25-t6040-5005-installer-flow-test/README.md)).
- **`podman machine ssh -- … sh -c '<script>'` splits the script into
  separate arguments,** so part of it runs on the VM instead of in the
  container. Pass container scripts as a file (as
  `scripts/t6040-build-nvmeroot-image.sh` does).
- **Daily kernels are built with `NO_KVM=1` (5007).** See "Core boot".

## Durable bring-up results

### Core boot

- T6040 CPU-start offset `0x88000` and the 4E+5P+5P topology are verified.
- Locked system-register accesses require the T6040 AIC/idle handling carried
  by the Wallace patches.
- DAPF entries that trap on T6040 are skipped while the required MTP DART path
  remains available.
- PMGR generation and the current power-domain layout are sufficient for boot.
- The watchdog transfers from m1n1 to Linux.
- **KVM breaks reboot on T6040 (5007, 2026-10-25).** With `CONFIG_KVM=y`,
  `reboot -f` reaches `syscore_shutdown` → `kvm_shutdown` →
  `kvm_timer_cpu_down` → `aic_fiq_set_mask`, whose IMP-DEF sysreg write
  (`d51df160`, the vtimer FIQ mask) traps because the kernel is not at EL2:
  Oops (Undefined instruction), and the machine hangs instead of rebooting.
  It runs after `device_shutdown`, so storage is already safe. Fix for daily
  images: kbuild `NO_KVM=1`; 5008 B then showed `reboot: Restarting system`
  with no Oops ([r3](../evidence/2026-10-25-t6040-211-r3-clean-shutdown-durable.md),
  [5008](../evidence/2026-10-25-t6040-5008-A-B.md)). A guard in
  `aic_fiq_set_mask` for non-EL2 kernels is the alternative, not done.

### Boot object and enrollment

- Direct raw m1n1 is sufficient; U-Boot is optional.
- The object layout is m1n1 plus bootargs, compressed kernel, DTB, compressed
  initramfs, and terminator.
- The former enrolled-boot reset loop was caused by total object length not
  being 16 KiB aligned.
- Alpine and Ubuntu RAM roots boot untethered.
- The dual-mode loader provides a short USB-serial window and otherwise boots
  normally.
- A T6040 U-Boot Image has already been entered through m1n1. The handoff armed
  m1n1's 20-second watchdog; the WDT-less U-Boot candidate then warm-reset back
  to the enrolled proxy exactly as intended (ticket 131,
  `evidence/2026-07-25-t6040-uboot-stage2-banner-result.md`). This is a proven
  recovery backstop for future removable stage-2 first lights, not yet a
  no-media selection protocol.

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
  Keyboard`. Before ticket 230, the trackpad gap was event delivery; touch
  and haptics are now proven, with daily integration remaining.
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
  the observed outcome is fail-stop. This does not prove that a
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
- **m1n1 PCIe initialization is once per power cycle, not once per m1n1
  instance.** Ticket 168 ran `pcie_init()` through the proxy and then entered a
  chainloaded m1n1 whose kboot path ran it again; the second initialization
  synchronously aborted at `0x41705a000` in the port-2 PHY-IP window and
  rebooted. A clean-boot retry worked. The in-instance `pcie_initialized` flag
  cannot protect across chainloads. Therefore an SD-capable U-Boot may not
  blindly run its active Apple PCIe setup after the current m1n1 kboot handoff;
  the stage boundary must assign the reset/PHY sequence to one owner.

### SD

- Built-in MMC, SDHCI-PCI, and exFAT support expose the GL9755 card as
  `mmc0` and `/dev/mmcblk0p1`.
- File write, sync, unmount, reboot, remount, and hash persistence are proven.
- The persistent-root prototype stores a 6 GiB ext4 loop image on the existing
  exFAT partition without repartitioning or formatting it.
- At `maxcpus=1`, the loop root reaches ttydc0 and OpenRC and retains writes.
- Panic testing left exFAT and ext4 unclean. Ticket 215 owns repair; ticket 216
  owns the staged PID-1 shutdown pivot and post-shutdown clean checks.
- **The clean-shutdown pivot is gated by a host harness** (ticket 3006):
  `scripts/t6040-test-sdroot-shutdown.sh` runs the real init block, inittab,
  powerctl and shutdown program under real exFAT/ext4/loop mounts with OpenRC
  0.63.2's mounts replayed. It needs no rig or card. `/run` must be init's own
  tmpfs, or OpenRC mounts over it and hides `/run/initramfs`.
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
  differences were candidates; none turned out to be the cause.
- **Linux reads work (6001 run 3, 2026-10-24).** The assert was the IOQ size:
  the 0x1210 fields are zero-based, and the driver wrote 64 for 64-entry rings
  (upstream and m1n1 write 63). With 63, 16,384 direct 16 KiB reads ran
  through about 256 CQ wraps at `maxcpus=1`, byte-identical across four passes,
  zero writes, clean full dmesg
  ([evidence](../evidence/2026-10-24-t6001-run3-16384-reads-no-cq-wrap-assert.md)).
  Sustained reads, multi-CPU and the 227 teardown UAF are unproven.
- The `APPLE SSD AP1024Z` (`apple-nvme`) exposes one controller with **three
  namespaces**: n1 1,954,210,120 sectors (the 1 TB disk; p1–p4 as of 5008 A, 2026-10-25), and Apple
  auxiliary n2 at 6,144 sectors (3 MiB) and n3 at 262,144 (128 MiB). Gates must
  pin this topology rather than reject a second namespace.
- **Linux writes work (211 stage 1, 2026-10-25),** with write-through: r2
  wrote 1 GiB in about 2.6 s (about 410 MB/s) and r3 another 1 GiB, each to the pinned exFAT
  `linux` partition `nvme0n1p3`, read-back matched after `drop_caches`, and
  whole-disk writes equalled p3 writes
  ([r2](../evidence/2026-10-25-t6040-5006-flush-unsupported-211-write-r2-pass.md),
  [r3](../evidence/2026-10-25-t6040-211-r3-clean-shutdown-durable.md)).
  Read-back runs at about 210 MB/s, bound by sha256 on one core.
- **ANS2 rejects NVMe Flush.** Linux's Flush (opcode 0, namespace NSID, TCB
  not zeroed) fails with `host_ans2.c:1616: cmd parsing error … fast decode
  err 0x7`, `BAD_CMD`, NVMe status 2 (`sc 0x2`, Invalid Field), so
  `conv=fsync` and every PREFLUSH request fail
  ([write1](../evidence/2026-10-25-t6040-211-write1-flush-badcmd.md)). The
  5006 m1n1 proxy probe sent m1n1's own minimal Flush (zeroed TCB,
  `dma_flags=3`) to nsid 1 and to broadcast `0xFFFFFFFF`: both status 2, link
  alive, LBA 0 unchanged. Admin delete-SQ/CQ also returns status 2, from both
  m1n1 and Linux. How macOS makes ANS2 durable (possibly a vendor command) is
  unknown.
- **Durability model.** Without Flush the controller keeps the most recent
  writes in a volatile cache and does not commit them by itself, even after
  1–2 idle minutes. Large writes push older data out to flash; the small
  trailing metadata stays cached. r2 survived a hard reset with its 1 GiB
  intact but lost `pattern.sha256` (written last) and the exFAT dirty-bit
  clear. A controller shutdown commits the cache: `reboot`/`poweroff` →
  `device_shutdown` → `apple_nvme_shutdown` (CC.SHN, then RTKit power-down),
  and the firmware logs `NVMe shutdown start` and `saveCtx 1 took 599 ms`
  (678 ms in 5008 B). r3's verify after a hard reset found everything. So:
  **any system that mounts the SSD read/write sets
  `/sys/block/nvme0n1/queue/write_cache` to `write through` before the mount
  and shuts down through the `reboot`/`poweroff` syscall.** A crash or hard
  reset still loses the last writes.
- **The daily SD-root DTB (`c5c3b4c3`) keeps NVMe disabled.** The nvmeroot DTB
  (`6d2d3da6`) enables only the three ANS nodes; 5008 A booted it with the full
  daily driver set and 6001's tester passed
  ([5008 A/B](../evidence/2026-10-25-t6040-5008-A-B.md)).
- **Installer false STOP (5008 B).** The installer's `others()` check hashed
  whole `/sys/block/*/stat` lines, reads included, and the new
  `findfs UUID=` reads every block device's superblock: p1/p2/p4 showed 5
  reads each and n2/n3 6, with zero writes. A write-confinement gate must
  compare the write, discard and flush fields only (fixed in `4389c3d`). The
  host flow test had stubbed `others()`, so it could not catch this.

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
- Ticket 305 runs 1--4 did **not** touch the real a1 controller. The fixture
  copied `/arm-io/nub-spmi-a1`'s raw child-bus address `0x309198000` into
  Linux `/soc`, whose `ranges;` is identity. The captured ADT maps `/arm-io`
  through parent base `0x200000000`, so the CPU physical address is
  `0x509198000` -- exactly what the July m1n1 path obtained through
  `adt_get_reg()` and used successfully. Ticket 3000 records the full
  translation/MMU audit. Ticket 3008 corrects only the DT node/reg, retains
  `ps_nub_spmi_a1`, hpm2 SID `0x0c`, and disabled NVMe, and produced two clean
  byte-identical DTBs (`eaf8cceb...`). Independent exact review 3009 passed;
  attended ticket 305 retains its fixture and execution gates. Apple-specific init and
  print-instrumentation work are fallback only if this corrected address
  stalls.
- **305 run 6 (2026-10-24): a1 SPMI works.** At `0x509198000` both
  `apple-spmi` controllers bound with no hang, SError or DART fault, the first
  time Linux drove the real a1 controller. hpm2 enumerates as SPMI device
  `1-0c`, but `tps6598x-spmi` probe returned a silent `-ENODEV`: no typec
  class, no VBUS
  ([evidence](../evidence/2026-10-24-t6040-305-run6-a1-physfix-probes-hpm2-enodev.md)).
- `spmi-apple` implements only `read_cmd`/`write_cmd`. Without `.cmd`,
  `spmi_cmd()` returns `-EINVAL` before any MMIO, so the 0001 probe's
  unchecked WAKEUP never reached the bus. `t6040-spmi-wakeup-and-tipd-probe-diag.patch`
  (f430d1f) adds a WAKEUP-only `.cmd` (opcode 0x13, word `0x00008c13` for SID
  0x0c, matching m1n1) and fails closed. Review PASS-with-notes
  ([review](../evidence/2026-10-24-t6040-pdwake-patch-independent-review.md));
  hardware proof is pending. VBUS is still not proven.

## October upstream operating knowledge

Source: [34-day IRC review](../evidence/2026-10-24-asahi-dev-review.md), with
saved transcript and source hashes. These are external observations, not new
Wallace hardware results. Offline integration/tracing plans are 6002/6003.

- October 5 J614s NVMe enumeration and benchmark success required built-in
  RTKIT/NVME_APPLE/SART. Verify actual kernel/config/modules before blaming ANS.
- October 3 namespace loss was bisected to `c20bba234f3e` controller-state
  handling; the earlier reg9 theory was retracted. Keep distinct from CQ wrap.
- M4 Pro MacBook display topology is disp0 + dispext0/1; mini differs. Live ADT
  takes precedence over template ADT when deciding whether board nodes exist.
- The October 8 upstream-style HID DT failed wakeup; Yuka's rebased older
  `t604x-old-dchid-working` branch worked. Preserve proven v2 input behavior.
- m1n1 WFI bootargs fix 689 and chainload repair 719 are merged. Refresh paired
  target/host versions together; SPTM support alone is insufficient for M4.
- M4 HV login-screen tracing is usable, but post-login hangs persist. AMCC
  interrupt masking is a workaround with unknown mapping/cache implications.
- Early asahi 7.2 rebase GPU/import/USB regressions received later fixes. Resolve
  corrected tag SHAs; the first 7.2.12-1 tag briefly pointed at the wrong base.
- Additional USB/CIO config dependencies and regmap lockdep fixes matter on a
  refreshed stack. They do not establish T6040 high-speed PHY support.

### October convergence audit (6002, offline)

[Property/patch map, immutable pins and regression sequence](../evidence/2026-10-24-upstream-convergence-audit.md).
Corrected Asahi `asahi-7.2.12-2` resolves to
`2bb9d16f967f11e533a851b13b148a708d59b4f3`; it already has the cpufreq
`1000UL` fix and `idle=nop`. Its delay path still uses WFIT/WFET unless
`arm64.nowfxt` clears the feature; `idle=nop` alone does not cover that path.
The raw-boot AIC skip lives in local commit `08c0e68f…`, **not** in the
current `flokli-code.patch` file, despite the harness comment.

The pinned NVMe core allows NEW → RESETTING. Mainline reverted the separate
namespace-init regression in `5755f1bd0217ffe3c5cf85467bf6b0680f398265`;
the mail's suggested CONNECTING workaround was retracted. None fixes the
local CQ-wrap assert by implication. Yuka's current M4 driver/DT uses one
widened reg9 aperture; keep Wallace's proven split and firmware gates. Its
full board DT selects SD port02/DART2, conflicting with our captured bridge1
and proven port01 path. Treat these as separate migrations, not cleanup.

Both Asahi's and Yuka's retrieved old HID drivers still send the four-byte
v1 power request; HID v4 is keyboard-only. Preserve local nine-byte v2,
bounded HIDF upload, typed devices and ttydc0/nbcon. New Asahi has a SoC FIFO
provider with the same APPLE_DOCKCHANNEL config symbol as our mailbox provider;
source assembly must select exactly one. Ticket 6004 owns that offline work.
Historical `parts/21-dt-nvme` and `t604x-old-dchid-working` refs were unavailable;
surviving component pins are not the exact externally tested branch.

## Corrections and dead ends

Do not repeat these without new evidence:

- **USB-root source gates are not a hardware boot result (6005, October24).**
  The new, separately named init originally ignored bootstrap/devtmpfs and
  handoff-directory failures and rejected valid quoted Xorg layout syntax.
  These are fixed:41 intercepted PID1 startup cases pass. Six contained
  real-OpenRC/ext4 shutdown cases pass, including failure stops; the host
  shutdown fixture uses a shell PID1 and blocks power actions, so it does not
  establish BusyBox-init power dispatch or three actual cold boots. A clean
  fsck after killing a failed test namespace is not a successful shutdown.
  The historical098 root remains unchanged; the separate root profile has
  two matching archives, but physical109 identity and final initramfs review
  remain open. [Evidence](../evidence/2026-10-24-usb-root-verified-init.md).
- **October cross-generation and cross-failure shortcuts.** Base-M4 USB is not
  M4 Pro/TB5 support; secondary-start improvements are not a demonstrated fix
  for fault 205; KVM SEIS workarounds address guests; M5 ANS/SART4 domains must
  not be copied into T6040. No blanket DAPF/PCIe bypass belongs in the daily
  baseline. p3s game success did not establish MM reliability: a nondeterministic
  GCC failure remained on October 24.
- **New upstream submission means tested J614s replacement.** October's HID
  wake failure and board-specific display domains disprove that shortcut.
  Compare, pin and validate before replacing working local components.
- **The staged SD-root clean shutdown as working (corrected 2026-10-24).** It
  never ran on the device, and three defects each defeat it. OpenRC mounts a
  tmpfs over a plain `/run` (powerctl refuses; a raw SIGQUIT halts with both
  filesystems mounted). BusyBox 1.35 `mount -o remount` needs `/proc/mounts`,
  which the pivot never mounted. OpenRC's `/dev/*`, `/sys/*` and `/run`
  submounts make the old root EBUSY. Fixed scripts and the harness are in
  [3006 evidence](../evidence/2026-10-24-t6040-3006-sdroot-shutdown-regression.md).
  Object `bdd8cc86…` predates the fix. Also: **Alpine 3.22's BusyBox
  1.37.0-r20 silently ignores `::restart`** (aports `c792a061` fixed it in
  3.23+), so never build an SD root from a 3.22 rootfs.

- **`t6040-nvme-apple-flush-tcb.patch` as the Flush fix (2026-10-25).** The
  theory was that Linux's non-zeroed TCB and `dma_flags` made ANS2 reject
  Flush. 5006 refuted it: m1n1's zeroed-TCB encoding fails the same way for
  nsid 1 and broadcast. The patch stays behind the opt-in `NVME_FLUSH_TCB`
  kbuild flag and is not in any payload.
- **A parked-shell listing as proof that NVMe data persisted (2026-10-25).**
  After 211 write run 1, `fsck.exfat -n` at the parked shell showed the test
  directory and file (19/97). After the `macvdmtool reboot` hard reset they
  were gone (18/96). Data reported as written was only in the controller's
  volatile cache. Persistence is proven only by a verify on a later boot, after
  the same kind of reset the daily driver will see.
- **Treating software queue-depth agreement as proof of the ANS2 firmware ring
  size (reopened 2026-09-20).** The earlier wrap investigation did not establish
  how firmware interprets register 0x1210. The upstream ANS2 implementation
  explicitly identifies it as zero-based IOQ sizes and says Create Queue qsize
  is ignored. Our Linux driver writes 64 there for 64-entry rings; upstream and
  local m1n1 write 63. This is specific new evidence for ticket 6000/6001, not a
  reason to repeat generic depth/batching/doorbell experiments. Hardware
  validation is pending; neither NVMe reads nor writes are newly signed off.
  **Resolved for reads, 2026-10-24:** 6001 run 3 with the zero-based size
  passed about 256 CQ wraps, so this was the Linux CQ-wrap cause. Writes
  passed on 2026-10-25 (211, write-through).

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
  fail-stop in that test. Do not claim observed silent corruption, or extend
  this bounded result into proof of safety for faulting processes/writeback.
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
- Treating ADT `/arm-io/nub-spmi-a1` raw `reg[0] = 0x309198000` as a Linux
  CPU-physical `/soc` address, or treating ticket 305 runs 1--4 as proof that
  the real a1 controller stalls. `/arm-io/ranges` translates it to
  `0x509198000`; test the reviewed corrected DTB before proposing controller
  initialization or MMIO instrumentation. **Confirmed by 305 run 6
  (2026-10-24):** a1 binds and works at `0x509198000`.
- Treating `spmi_command_wakeup()` as sent on Apple SPMI (2026-10-24). Before
  f430d1f, `spmi-apple` had no `.cmd`, so the call returned `-EINVAL` silently.
  The 2026-08-18 review recorded WAKEUP as sanctioned without checking that the
  controller could emit it. Check the return value of every bus command.
- Losing the evidence log (2026-10-24). `/dev/kmsg` is rate-limited by default
  (`printk_devkmsg=ratelimit`); 6001 run 3's tester PASS line was dropped
  (`init: 60 output lines suppressed`), so the formal checker could not pass.
  Boot payloads whose verdict goes through `/dev/kmsg` with
  `printk.devkmsg=on`, or keep their output below the limit. Never run
  `dmesg -c` before preserving the full ring buffer: 305 run 6 lost its full
  boot dmesg that way. Match upper-case fault tokens (`BUG:`, `SError`,
  `panic`) case-sensitively: a case-insensitive `BUG:` matched
  `printk: debug:` (from `ignore_loglevel`) and false-stopped 6001 run 2.
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
| 2026-08-19 | USB2 data path verified live and no-child disambiguated to no VBUS; PD image runs then hung because the DT used raw `/arm-io` `0x309198000` as a CPU physical address. Offline audit 3000 proved `0x509198000`; candidate 3008 rebuilt that DT-only correction twice byte-identically (`eaf8cceb...`). Await independent exact review, then resume attended 305. |
| 2026-10-24 | **Linux NVMe reads work**: 16,384 direct reads through ~256 CQ wraps at `maxcpus=1` with the zero-based ANS2 IOQ size (6001 run 3). 305 run 6: a1 SPMI binds at `0x509198000`; hpm2 probe `-ENODEV` traced to the missing `spmi-apple` `.cmd`, WAKEUP fix reviewed. SD-root shutdown fixed in a host harness (3006) |
| 2026-10-25 | **Linux NVMe writes work** (211: 1 GiB at about 410 MB/s, p3 only, write-through). ANS2 rejects NVMe Flush in any encoding (5006); a clean controller shutdown (CC.SHN, `saveCtx`) makes cached writes durable across a hard reset (r3). KVM reboot oops fixed by `NO_KVM` (5007). NVMe daily root: new daily+NVMe kernel `2234baad` reads NVMe with every driver up (5008 A); 16 GiB root image installed on p3 (5008 B); first NVMe-root boot pending. 305 run 7: WAKEUP ACKed, register select mis-encoded; `pddiag` built for run 8 |

Detailed transcripts, hashes, retractions, and per-experiment stop conditions
remain in dated files under `evidence/` and in Git history.
