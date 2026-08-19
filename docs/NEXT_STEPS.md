# T6040 Linux bring-up — next steps

Current as of 2026-08-19. This file states priorities and stop conditions.
Exact work items, hashes, dependencies, and approval state live in
`tickets/*.json`.

## 0. The current objective: a practical daily driver

**CJ's direction, 2026-08-03 (supersedes the previous upstream-first ordering).**
The goal is a machine that is actually usable, with six capabilities working
unambiguously:

| capability | state |
|---|---|
| SD read/write | reader and persistence proven; fixture needs `fsck.exfat` repair |
| USB read/write | device mode works; **USB2 host data path DONE 2026-08-19** (108) — dwc3 probes, right xHCI root hubs healthy. VBUS is the sole gap; the tps6598x SPMI PD driver is written and CJ-signed-off (231), attended run staged (305) |
| NVMe read/write | m1n1 reads stable; Linux asserts at the first CQ wrap; writes unproven |
| WiFi | works, including DHCP and routed traffic |
| Bluetooth | `hci0` present and working |
| Trackpad | **DONE 2026-08-19** (230): finger test PASSED — 37 950 events on `/dev/input/event0` and haptic click works. Daily-image integration remains (301) |

**Upstream reporting is explicitly deferred** — CJ: "we are not doing any
upstream reporting just now." Sections below that call an upstream report the
highest-value action are describing engineering value, not current priority.

Standing constraints for autonomous work:

- **NVMe writes are restricted to the exFAT `linux` partition**, verified by
  label *and* GPT type before any write, aborting on mismatch. No other
  partition on the internal SSD may be written (CJ, 2026-08-03).
- SD repair is a real `fsck.exfat`, not clearing the dirty flag (CJ, same).
- Chainload rather than enroll; the always-proxy rollback object stays enrolled.

## 1. Characterise and report the MM/SMP copy race

Tickets: **205** (umbrella), **217** (offline artifact), **209** (approved
rig run); **207** and **208** are done

The dependency-free BusyBox reproducer reliably distinguishes one from two
cores: the uninstrumented `maxcpus=2` kernel faulted twice in four runs
(ticket 208). Ticket 207's bisect then **refuted the ordering hypothesis**:
`smp_mb()` alone and a semantically irrelevant volatile read of the
destination — with no barrier at all — each suppressed the fault completely.
Any small perturbation before `copy_page()` hides it, so the race is not
located in `copy_highpage`; that is where the fault is taken, not where the
bug lives. The fault is a kernel-mode fault on a valid linear-map address,
which points at page lifetime/refcount or TLB-invalidation completion.

Round 18 settled the question that mattered most for daily use: **the bug is
fail-stop, not silent corruption.** With the fork-heavy reproducer running in
the background and a fault firing that killed it, twelve consecutive 64 KiB
copy-and-compare verifications in the surviving process were byte-identical
(`SAME=12, DIFFER=0`). The fault path — `die_kernel_fault` →
`arm64_force_sig_fault` → `make_task_dead` — is fail-stop by construction. So
`maxcpus>1` costs availability, not data. Bounded honestly: this does not prove
a process *hit* by the fault writes nothing bad before dying, nor that a fault
during page-cache writeback cannot reach storage.

Do next:

1. Turn the reproducer and the 207/208 results into an upstream-quality
   report for the Asahi and arm64 MM maintainers. This is the single
   highest-value action; the port may simply lack a known erratum workaround.
2. Ticket 217 (offline): build the byte-reproducible, storage-free diagnostic
   initramfs around the uninstrumented control Image and prove the stock
   arm64 oops already reports the logical CPU.
3. Ticket 209 (rig, consumes 217's artifact): characterise which CPU takes
   the fault and whether the victim differs in core type or cluster from the
   CPU that populated the page, using the controlled-online-set DTBs.
4. Keep the discipline: fresh boot per variant, at least four runs (the first
   is the most sensitive), constant storage/drivers/topology/workload, and an
   exact Image hash plus uniquely named transcript per result.

Pass: an upstream-visible report plus a victim-topology characterisation.
Do **not** ship any perturbation that merely suppresses the symptom; ticket
207 proved suppression is not evidence of a fix. A single clean run is not
evidence either.

## 2. Repair and harden the SD-root system

Tickets: **215**, then **216**; these close **204**

The SD reader and root image work at `maxcpus=1`: `switch_root`, ttydc0, OpenRC,
and persistence were observed. Later SMP panic tests left exFAT and ext4
unclean. Do not mount the root read/write again before ticket 215.

Do next:

1. Exact-review ticket 215's pinned repair image and automatic-only repair script.
2. Repair and repeat read-only checks for SD64 and the ext4 image.
3. Exact-review ticket 216's identity gates, early console, and shutdown pivot.
4. Apply the root configuration and boot it at `maxcpus=1`.
5. Power off through the PID-1 restart path; verify ext4 and exFAT are clean.
6. Preserve a uniquely named, hash-pinned transcript.

Use `maxcpus=1`. Ticket 205 proves that two or more CPUs can fault in kernel
page-copy paths; that is separate from SD storage.

Pass: the repaired root boots through ttydc0 and OpenRC, cleanly powers off,
and both filesystems pass post-shutdown read-only checks without repair.

Approved follow-ons **213** (i3 desktop on the SD root) and **214**
(WiFi/sshd/ntpd autostart, removing the serial tether) continue this track
once 215/216 restore a clean root.

## 3. Isolate the Linux NVMe CQ-wrap assert

Current facts:

- raw m1n1 reads survive several queue wraps;
- Linux enumerates namespaces and mounts the exFAT partition briefly;
- Linux asserts at its first I/O CQ wrap;
- queue depth, one outstanding I/O, tag value, CQ IRQ enable, batching, phase,
  and several address hypotheses have been tested or refuted;
- hard-IRQ completion remains an unmatched difference, not a proven cause.

Order:

1. **201:** capture and hash one complete modern RTKit crashlog with the
   logging-only decoder patch. Preserve the first transcript; do not retry an
   unchanged run.
2. **203:** produce two byte-identical builds of the per-driver threaded-IRQ
   discriminator and independently review the exact object.
3. **210 (approved):** run the reviewed discriminator against the assert.
   Hard-IRQ completion is the strongest surviving difference; boot the SD
   root at `maxcpus=1` once ticket 215 has restored a clean root, then drive
   sustained reads until the assert fires or the time box passes.
4. **195:** test live admin traffic in m1n1 only after its artifact and plan
   satisfy the normal gate.
5. **196/211:** defer NVMe writes until the CQ-wrap failure is understood or
   safely avoided. Ticket 211 then owns the write soak, and only within CJ's
   recorded authorization: writes via the mounted filesystem and raw writes
   to `p3` only — never raw writes to `/dev/nvme0n1` or any APFS partition.

Do not revive the refuted “wrong MMIO window,” non-zero tag, batching, or
simple queue-depth explanations without new evidence.

## 4. Keep the strict SD fixture sequence honest

Tickets: **199** then **200**

Ticket 193 already proved SD read/write persistence. Tickets 199/200 are a
stricter, hash-pinned fixture procedure and must not be treated as if they have
run.

- Ticket 199 is read-only: identify GL9755 and `SD64`, mount `ro`, list,
  hash one existing file, and unmount.
- Ticket 200 may run only after 199 is done and separately approved: mount
  read/write, create the one named test file, fsync, unmount, remount read-only,
  and verify content and SHA-256.

Neither ticket permits repartitioning, formatting, fsck, or unrelated card
changes. Ticket 200 must also respect the dirty-filesystem gate owned by
tickets 215/216.

## 5. Trackpad: DONE — daily-image integration remains

**Complete as of 2026-08-19** (ticket 230,
`evidence/2026-08-19-t6040-trackpad-finger-test-PASS.md`). The post-upload
command `0x40` is the MTP interface power request; J614s speaks only the 9-byte
v2 two-phase form; the patched v2 pair brings the pad to `Touch MT ready`
260 ms after `open()`. CJ's finger test then produced **37 950 events / 910 800
bytes** on `/dev/input/event0` with a hex dump of real multi-touch reports, and
**force-click haptics fire** (Taptic actuator up). Touch + haptics both live.

Do next:

1. Ticket 301: fold the patch (`t6040-dockchannel-hid-reset-contract.patch`)
   and the `a1f4131d` firmware blob into the daily sdroot image, two-build
   reproduce, preflight, new enrollable object — so the daily driver carries a
   working trackpad without a special image.

Any live attempt stays limited to the approved volatile HIDF blob
`a1f4131d…`; nothing else changed in the safety scope.

## 6. USB host/VBUS (active)

Tickets: **108** (USB2 data path — DONE, VBUS the sole gap), **303** (v2 rebuild,
built + binary-reviewed), **231** (PD driver — reviewed and **CJ-signed-off**),
**305** (attended PD/VBUS run, staged), **229** (R0 connector read,
attended-only), **109+** (block read-only and beyond, blocked)

Both blockers identified on 2026-08-04 are now solved offline; what remains
is review and rig time:

1. **dwc3 `-EINVAL` — fixed and VERIFIED LIVE (2026-08-19).** v2 of the PHY
   slice (`b7f02c3c…`) was rebuilt into the Jul-29 profile (303,
   `buildB` `80248306…`, binary-reviewed PASS) and re-run: the eUSB2 host
   sequence completed on first execution, dwc3 probed clean, both right
   xHCI root hubs up and persistent, zero DART faults
   (`evidence/2026-08-19-t6040-usb2-v2phy-rerun-root-hubs-restored.md`).
   **The USB2 data path is done.** No child appeared — VBUS is the sole
   remaining gap (or the S128 stick left the port since Aug 4; CJ settles
   that by looking).
2. **VBUS — driver written and reviewed, gated on CJ.** The tps6598x SPMI
   transport (231, `77fd00b`) reuses the whole tipd state machine over a
   paged select/window regmap bus matching the m1n1-live-proven protocol;
   the exact-source review
   (`evidence/2026-08-18-t6040-tps6598x-spmi-review.md`) found it sound and
   enumerates the sign-off table — probe = WAKEUP + reads + SSPS→S0, plus
   two new classes: `INT_MASK1` (0x16) write at probe, W1C `INT_CLEAR1`
   (0x18) per event. A draft DT connector node exists
   (`dts/t6040-j614s-dcuart-usb2-native-right-pd.dts`, hpm2 only,
   compile-validated, not runnable).

CJ **signed off the SPMI envelope 2026-08-19** (probe = WAKEUP + reads +
SSPS→S0, `INT_MASK1` 0x16 write at probe, W1C `INT_CLEAR1` 0x18 per event,
hpm2/right-port only via the DT gate). Remaining, in order: the attended
PD/VBUS live run (305) — including an R0 connector-state read (229) to learn
whether the right port already sources VBUS — then the PD-enabled image through
the normal build/review cycle. SPMI stays deny-by-default under
`SPMI_SAFETY.md`; the only described endpoint is right-port `hpm2`.

## 7. Parked tracks

- **GPU:** wait for a maintainer-endorsed T6040/G16 kernel, firmware ABI, m1n1,
  and Mesa stack. Do not relabel G14 support.
- **Standard stage 2:** ticket 191 may compare SD and NVMe storage designs
  offline. U-Boot lacks exFAT support, so SD stage 2 would require a FAT32
  partition; do not repartition the fixture without CJ.
- **Audio, camera, suspend, cpuidle, panel backlight:** retain as roadmap work;
  none blocks the current SD-root milestone.

## Global stop conditions

Stop on an async SError, DART fault, firmware panic, unexpected reset, console
loss before the planned boundary, artifact mismatch, access outside the ticket,
or any write not explicitly authorized. Preserve the first transcript and
return the rig in the state required by [COORDINATION.md](COORDINATION.md).
