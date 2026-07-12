# t6040 Linux bring-up — NEXT STEPS

Handoff state (2026-07-12): mainline Linux boots to a BusyBox shell on the
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
`-EINPROGRESS`. Extract the paired HIDF blob from this machine's macOS firmware
with `asahi-fwextract`, rebuild the initramfs with
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

The supported shape is now implemented and live-tested in build #14:
`patches/t6040-pmgr-t6041-quirks.patch` selects preserve-active and the two CPU
auto-enable exceptions from `apple,t6041-pmgr-pwrstate`; Linux `37339d595765`
removes the experiment-only properties from the standard DT. Review/clean the
draft for upstream, but no further policy bisection is needed.

Next, in leverage order:
1. Ask flokli for the J773s PMGR policy (draft only here; maintainer sends).
2. Register a real DockChannel printk console if pre-console attribution is
   still needed.

Done this session: raw determinism, requested core-infra and PMGR1 isolations,
live ADT regeneration, `no_ps` parent filtering, and safe always-on generation
(no policy by default; explicit legacy flag only).

## 3. Approve and run the first ANS/NVMe probe
The live ADT storage map is captured and committed as disabled nodes (Linux
`9cf4a92fa16f`): ANS ASC/mailbox, SART v3, NVMe/NVMMU, IRQs, and the two PMGR
dependencies. This path uses SART, not DART. Build the deliberately separate
candidate with `scripts/t6040-build-nvme-candidate.sh`; the current candidate
is built and verified, but do **not** boot it until the maintainer approves the
separate `Image-nvme` plus DTB and the normal Apple NVMe driver writes
summarized in `done/2026-07-13-t6040-nvme-map.md`. The existing BusyBox already
provides `fdisk`, `hexdump`, `mdev`, `find`, `mount`, and `umount` (but not
`blkid`), so no userspace rebuild is needed for the enumeration-only first
probe. Do not mount a namespace during that probe.

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
