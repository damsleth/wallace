# t6040 Linux bring-up — NEXT STEPS

Handoff state (2026-07-13): mainline Linux boots to a BusyBox shell on the
M4 Pro with working internal keyboard, watchdog, and a **fully remote dev
loop** — two-way m1n1 proxy AND Linux shell (`/dev/ttydc0`) over one DebugUSB
cable; reboot via `macvdmtool`. No screen-reading or physical access needed.
Operational details, recipes, and history: `DEVLOG.md`. Long-term: `roadmap.md`.
Read the DebugUSB link rules in DEVLOG before touching the rig.

## 1. Provision and test the J614s trackpad firmware
`event0` is Apple DockChannel Multi-touch and `event1` is the keyboard. The
transport's missing firmware loader and stuck-start error path are fixed and
live-tested in kernel build #12: repeated opens now independently request
`apple/tpmtfw-j614s.bin` and return `-ENOENT`, with no invalid resets or stale
`-EINPROGRESS`. Retrieve the paired HIDF blob from this target's Asahi ESP at
`vendorfw/apple/tpmtfw-j614s.bin`, or process its
`asahi/all_firmware.tar.gz` with `asahi-fwextract`, then rebuild with
`TRACKPAD_FIRMWARE=/path/to/tpmtfw-j614s.bin`, and retest motion. If MTP then
requests its reset GPIO, stop: the now-derived `gp1c` function resolves through
the ADT's `smc-pmu` node, and PMU writes are forbidden by the project rules.
No tactile click is expected yet (the haptic actuator is a separate interface).
Full finding:
`done/2026-07-12-t6040-trackpad-firmware.md`.

## 2. Review and upstream the proven T6041 PMGR quirk
The full 214-domain topology now boots to BusyBox **3/3** with the exact minimal
temporary policy: preserve firmware-active domains, disable only `disp_cpu`,
and skip auto-enable only on `dispext0_cpu` and `dispext1_cpu`. Both CPU skips
are individually necessary at bank granularity; the `sys`, `fe`, and five old
ANE exclusions are unnecessary. Legacy raw fails 3/3. Full matrix and hashes:
`done/2026-07-12-t6040-pmgr-matrix.md`.

The supported shape is now implemented and live-tested in build #14. The
two-patch draft starts with `patches/t6040-pmgr-t6041-bindings.patch`, then
`patches/t6040-pmgr-t6041-quirks.patch` selects preserve-active and the two CPU
auto-enable exceptions from `apple,t6041-pmgr-pwrstate`; Linux `37339d595765`
removes the experiment-only properties from the standard DT. The series passes
checkpatch and both binding schemas validate. No further policy bisection is
needed.

Next, in leverage order:
1. Ask flokli for the J773s PMGR policy (draft only here; maintainer sends).
2. If pre-userspace attribution becomes necessary, first add a bounded
   polled/atomic TX primitive to the DockChannel mailbox. Do not register the
   current `ttydc` kfifo/workqueue path as a printk console: it is not safe in
   atomic or panic context and can recurse through its own error printk.

Done this session: raw determinism, requested core-infra and PMGR1 isolations,
live ADT regeneration, `no_ps` parent filtering, and safe always-on generation
(no policy by default; explicit legacy flag only).

## 3. Force the storage parents actual-on before any ANS retry
The maintainer approved the exact CoastGuard writes. The retry established two
separate boundaries:

1. A handshake-only SART probe still reset, while a zero-MMIO SART probe booted.
   `patches/t8140-sart-defer-scan.patch` now defers the protected-entry scan
   until the first client has the complete ANS power context. With that fix,
   both the SART-only DT and the full DT with `nvme-apple` unloaded reached
   BusyBox.
2. Loading `nvme-core.ko` succeeded. Loading `nvme-apple.ko` reset the target.
   Yielding phase checkpoints made the exact last successful point
   `before ANS CPU control read`; the fatal operation is the first read of
   `0x209600044`, before any CoastGuard write, SART entry access, or namespace
   command.

Read-only ADT-derived PMGR inspection found that firmware leaves `ANS` at
`0x0f0000ff`: target and actual state `0xf`, with AUTO_ENABLE clear. Linux's
T6041 PMGR probe otherwise enables automatic gating before the NVMe module's
first access. `patches/t6040-pmgr-ans-no-auto.patch` adds an NVMe-only build
exception, and `dts/t6040-j614s-dcuart-nvme-ans-hold.dts` independently selects
the same existing bring-up policy. Both compile; the hypothesis is not yet
live-verified. The last diagnostic reached BusyBox, but its log relay replayed
historical PMGR output and the m1n1 proxy then remained unresponsive after the
documented kisd/re-entry recovery. Stop live work until DebugUSB is healthy.

The recovery helper now makes the fresh kisd PTY raw and attaches its own
reader before DebugUSB traffic. A later recovery confirmed the complete m1n1
startup packet, but proxyclient then timed out while 3.2 KiB of historical
Linux output remained queued. The next reboot stopped after iBoot Stage2, and
then fell through to Apple's "macOS on the selected disk needs to be
reinstalled" screen instead of launching m1n1. The following DebugUSB VDM
failed; live work stopped with kisd detached. This proves only that Apple's
boot chain identified the selected system volume, not that Linux NVMe ran.

Run the recovery helper; it now requires a healthy `Running proxy` and three
unchanged console-size samples before returning. Then boot only the prepared
trace set and relay new `trace:` lines, not the historical PMGR backlog:

- `Image-sart-trace`:
  `0c4880522c4793629f6e9a25ea164c911801e67754ae43cd3a6b5b274e20e8e6`;
- `t6040-j614s-dcuart-nvme-ans-hold.dtb`:
  `cc2c48e30a09080117222d5f4c9fb795dfd6bb338d2cf26b23085ad947ffbefb`;
- `initramfs-dcuart-nvme-ans-hold.cpio.gz`:
  `ae80f82033e5f0d683ac09a3fa61e67c3c63e8a7c1be7593a0fd7fe687732873`.

The exact set was finally booted as Linux #24. `nvme-core.ko` returned zero;
`nvme-apple.ko` watchdog-reset the target. That boot did not have a kmsg relay,
so the absence of trace messages on ttydc does **not** move the fatal boundary
earlier than the prior `before ANS CPU control read` result. For the next
single retry, use the newly built trace-relay initramfs below and add
`EXTRA_BOOTARGS=t6040.trace_relay=1`; it relays only current-boot `trace:` lines
before the shell command is run.

- `initramfs-dcuart-nvme-ans-hold-trace.cpio.gz`:
  `8942b1bd009cd9fe0adeadea3de60d6f068120ae2b8327e0ae1df2c852f40ea5`.

Use the same Image and DTB hashes above. For agent-driven helpers, set
`T6040_KEEPALIVE=1` so kisd and the tty reader survive the automation shell.

That corrected retry is now complete. Its current-boot trace was identical to
the original through `reset work entered`, then stopped at
`before ANS CPU control read`. Therefore preserving ANS firmware state and
skipping AUTO_ENABLE did **not** move the boundary; the ANS auto-gating
hypothesis is disproven. Do not repeat this NVMe module load unchanged.

Next, boot the same trace-relay set but do not load either NVMe module. Capture
the software genpd state first (DEBUG_FS is enabled):

```sh
mount -t debugfs debugfs /sys/kernel/debug
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary \
  | grep -E 'ans|apcie|fab3'
for d in ans apcie_sys_st0 apcie_sys_st1 apcie_phy_sw; do
    echo "--- $d"
    cat "/sys/kernel/debug/pm_genpd/$d/current_state"
done
```

This is read-only software-state attribution. Use it to decide whether a
separately reviewed raw PMGR-state trace is warranted; do not perform another
ANS MMIO read merely to reproduce the same SError.

Captured: the summary and per-domain files report `on` for `ans`,
`apcie_sys_st0`, `apcie_sys_st1`, and `apcie_phy_sw`; the filtered summary also
shows `fab3_soc`, `apcie_st0`, `apcie_st1`, and `apcie_gp` on. Linux therefore
does not believe the storage power chain is off.

The bounded raw-state diagnostic is now built and host-verified.
`patches/t6040-nvme-pmgr-snapshot-debug.patch` is selected only by the boolean
`apple,pmgr-snapshot-stop` in
`dts/t6040-j614s-dcuart-nvme-pmgr-snapshot.dts`. After normal allocation has
attached the declared genpd chain, it follows only those existing DT
`power-domains` phandles, reads each provider's declared scalar `reg` through
its parent PMGR syscon, and returns before `nvme_add_ctrl()`. Reset work cannot
queue, so no ANS, CoastGuard, SART-entry, mailbox, NVMe register, or storage
command is reached. Its diagnostic exit intentionally retains the genpd links
until reboot instead of requesting a cleanup power transition. Do not unload
the diagnostic module; reboot after collecting the trace.

Prepared artifacts:

- `Image-nvme-pmgr-snapshot`:
  `1a056fd855f2d56508e90dc5b9a789d8dc6dcaaf8f7b2284b759756213056541`;
- `t6040-j614s-dcuart-nvme-pmgr-snapshot.dtb`:
  `396d6ad1318764658728b4eb0b67a3961965428031e0aa52b2b59515633a977a`;
- `initramfs-dcuart-nvme-pmgr-snapshot.cpio.gz`:
  `7d44ee376cca2ca0caf44a713b329319b39e502dd29efa41f0b37f1e856be94c`;
- `nvme-core-pmgr-snapshot.ko`:
  `5e61ba16697daa382c5bb614fdaf3d5948a3818c11a630d5766e3b88ead36af7`;
- `nvme-apple-pmgr-snapshot.ko`:
  `21f00d39ad4f8f86df03c403d8d683addc6e4a65c2a8b204e2f7a57adac611f4`.

The single snapshot attempt is complete. Linux #25 reached BusyBox,
`nvme-core.ko` returned zero, and the diagnostic Apple module printed its full
snapshot plus `stopping before ANS MMIO`. The shell then answered two liveness
markers. The four storage values exactly match the earlier m1n1 snapshot:

```text
ans            raw 0x0f0000ff  target f  actual f  auto 0
apcie_phy_sw   raw 0x1400024f  target f  actual 4  auto 1
apcie_sys_st0  raw 0x1000030f  target f  actual 0  auto 1
apcie_sys_st1  raw 0x1000030f  target f  actual 0  auto 1
```

The genpd summary's `on` result was logically correct but incomplete:
`apple_pmgr_ps_is_active()` treats target-active plus AUTO_ENABLE as on even
when the actual state is clock-gated (`4`) or power-gated (`0`). Thus ANS itself
is fully active, while NVMe's other direct domain, `apcie_phy_sw`, is
clock-gated and both of that domain's `apcie_sys_st*` parents are power-gated
immediately before the fatal read.
This is the first evidence-backed new hypothesis since ANS auto-gating was
disproved.

Next, prepare and review a second diagnostic that uses only the existing PMGR
domain callbacks and DT chain to force these parents to actual state `f`,
snapshots before/after, and still exits before ANS MMIO. Do not retry the ANS
read in the same step. If that transition is safe and all actual fields reach
`f`, a separately reviewed one-read retry becomes justified. Never mount,
repair, format, flush, or write the namespace. Full evidence is in
`done/2026-07-13-t6040-nvme-map.md`; the exact transcript is
`logs/t6040-console-20260713-nvme-pmgr-snapshot.log`.

## 4. Upstream / share
- Post the drafted writeups: `done/2026-07-10-t6040-smp-writeup.md`,
  `done/2026-07-10-t6040-cpufreq-writeup.md` (#asahi-dev).
- Keep the curated code-only branch `t6040-bringup` (worktree
  `~/Code/m1n1-clean`) in sync with any new src/ changes on main.
- Report the dockchannel-uart dead-IRQ finding + poll-mode patch to the
  dockchannel-branch authors (yuka / Michael Reeves) — t8140 may differ.

## Parked (revisit after pmgr)
- USB gadget console → gadget-Ethernet + SSH (EP0 dies post-enumeration;
  `done/2026-07-11-t6040-usb-gadget-plan.md`).
- cpufreq throttle offsets (t6030 offsets SError on t6040 P-clusters; needs RE
  or #asahi-dev answer).
- ATC PHY tunables (USB3/TB) — blocked on t6040 PHY reg-bucket offsets;
  USB2-only fallback is fine for now.
