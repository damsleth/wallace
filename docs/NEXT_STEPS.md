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

Established (mechanism detail and method in [DEVLOG.md](DEVLOG.md) "CPU" and
`evidence/2026-08-03-t6040-205-smp-cow-investigation.md`):

- the dependency-free BusyBox reproducer distinguishes one from two cores
  (`maxcpus=2` faulted twice in four runs, ticket 208);
- ticket 207's bisect **refuted the ordering hypothesis** — `smp_mb()` and a
  semantically irrelevant volatile read each suppress the fault, so the race is
  not in `copy_highpage`; the kernel-mode fault on a valid linear-map address
  points at page lifetime/refcount or TLB-invalidation completion;
- the bug is **fail-stop, not silent corruption** (round 18): with a fault
  firing and killing a concurrent process, twelve consecutive 64 KiB
  copy-and-compare checks were byte-identical. So `maxcpus>1` costs availability,
  not data. Not proven: that a process *hit* by the fault writes nothing bad
  before dying, or that a fault during page-cache writeback cannot reach storage.

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

## 2a. Stable enrolled SD stage 2 (active, offline-first)

Tickets: **3010** (architecture, done), **3011** (PCIe/SD ownership, done), **3012**
(one-shot proxy cookie), **3013** (SD U-Boot), **3014** (bundle tooling),
**3015/3016** (compose + independent review), **3017** (read-only tethered
first light), **3019** (physical-media preflight). Ticket **3018** adds USB
only after the VBUS track has a bounded result; **3020** packages and validates
the exact Linux handoff on a synthetic FAT image.

The target is:

```text
iBoot -> enrolled aligned m1n1 -> short DTR proxy window -> U-Boot
                                                        |-> SD -> Linux
                                                        |-> USB -> Linux later
                                                        `-> no media -> warm reboot -> Running proxy
```

The architectural contract is
[recorded here](../evidence/2026-08-19-t6040-removable-stage2-architecture.md).
The enrolled object changes rarely; Image, J614s DTB, initramfs and their
manifest are the daily files. SD comes first. The current card's outer exFAT
filesystem is not a U-Boot boot filesystem, and nothing here authorizes
repartitioning it. Ticket 3019 must prefer a separately identified development
card or stop for an exact maintainer choice.

Do next, entirely offline:

1. Implement and host-test the clear-before-use, one-shot warm-RAM proxy reason
   (3012). Do not use NVRAM or invent a direct return from U-Boot.
2. Apply ticket 3011's resolved boundary while building the SD target (3013):
   m1n1 performs exact `gP19` power and the one common-PHY/link initialization;
   U-Boot attaches only if the link is already up and owns DART1/PCI/MMC above
   it. Link-down must not trigger a second port setup.
3. Build the SD-only U-Boot target twice, then build and independently review
   the aligned composed object (3013, 3015, 3016).
4. Build the board-bound FAT32/FIT-or-manifest tooling on synthetic images
   (3014). The daily profile stays `maxcpus=1`, ANS/NVMe disabled, trackpad
   enabled, and Norwegian-layout compliant. Ticket 3020 then validates the
   exact `booti` handoff and daily bundle without touching a card.
5. Only then propose 3017 for cross-review and approval. It chainloads while the
   rollback remains enrolled, reads only PCI/MMC/GPT identity from SD64, and is
   expected to warm-reboot once back to the enrolled proxy because no valid FAT
   bundle exists.

Pass for this phase: one reviewed tethered run proves the GL9755/MMC path and a
clean return to the enrolled rollback proxy, with no media write or enrollment.
Physical bundle installation and untethered enrollment get separate tickets
only after an exact removable target and hashes exist.

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

**Complete as of 2026-08-19** (ticket 230, touch + haptic click; finger-test
numbers and the `0x40`/v2 decode are in
`evidence/2026-08-19-t6040-trackpad-finger-test-PASS.md` and
[DEVLOG.md](DEVLOG.md) "Trackpad").

Do next — **ticket 301:** fold the patch
(`t6040-dockchannel-hid-reset-contract.patch`) and the `a1f4131d` firmware blob
into the daily sdroot image, two-build reproduce, preflight, new enrollable
object, so the daily driver carries a working trackpad without a special image.
Any live attempt stays limited to the approved volatile HIDF blob `a1f4131d…`;
nothing else changed in the safety scope.

## 6. USB host/VBUS (active)

Tickets: **108** (USB2 data path — DONE, VBUS the sole gap), **303** (v2 rebuild,
built + binary-reviewed), **231** (PD driver — reviewed and **CJ-signed-off**),
**3000/3008** (a1 address correction — audited and byte-reproduced offline),
**3009** (independent corrected-DTB review), **305** (attended PD/VBUS run,
blocked on 3009), **229** (R0 connector read, attended-only), **109+** (block
read-only and beyond, blocked)

Both 2026-08-04 blockers are solved offline (mechanism and live-run detail in
[DEVLOG.md](DEVLOG.md) "USB and Type-C"):

1. **dwc3 `-EINVAL` — fixed and VERIFIED LIVE (2026-08-19).** The v2 PHY slice
   (303, `buildB` `80248306…`, binary-reviewed PASS) probes clean, both right
   xHCI root hubs up and persistent, zero DART faults. **The USB2 data path is
   done.** No child appeared — VBUS is the sole gap (or the S128 stick left the
   port; CJ settles that by looking).
2. **VBUS — tps6598x SPMI transport written and reviewed** (231, `77fd00b`;
   review `evidence/2026-08-18-t6040-tps6598x-spmi-review.md`). A draft
   hpm2-only DT connector node exists
   (`dts/t6040-j614s-dcuart-usb2-native-right-pd.dts`). Ticket 305 runs 1--4
   accidentally put the ADT's raw `/arm-io` address `0x309198000` under
   identity-mapped Linux `/soc`; they therefore never accessed the real a1
   controller and do not prove an a1 hardware stall. Ticket 3000 proved the
   translated CPU physical address is `0x509198000`. Ticket 3008 built the
   corrected DTB twice from clean trees, byte-identical (`eaf8cceb...`), with
   hpm2 as the sole PD endpoint and NVMe disabled.

CJ **signed off the SPMI envelope 2026-08-19** — the exact permitted operations
are in `docs/SPMI_SAFETY.md` (Entry 1, hpm2/right-port only via the DT gate).
Remaining, in order: independent exact-artifact review (3009) of the corrected
`eaf8cceb...` DTB; then the attended PD/VBUS live run (305), including an R0
connector-state read (229) to learn whether the right port already sources
VBUS; then the PD-enabled image through the normal build/review cycle. SPMI
stays deny-by-default; the only described PD endpoint is right-port `hpm2`.

## 7. Parked tracks

- **GPU:** wait for a maintainer-endorsed T6040/G16 kernel, firmware ABI, m1n1,
  and Mesa stack. Do not relabel G14 support.
- **Internal-NVMe stage 2:** ticket 191 remains a separate parked design. It is
  not the active removable SD-first path and remains blocked by the NVMe fault
  track.
- **Audio, camera, suspend, cpuidle, panel backlight:** retain as roadmap work;
  none blocks the current SD-root milestone.

## Global stop conditions

Stop on an async SError, DART fault, firmware panic, unexpected reset, console
loss before the planned boundary, artifact mismatch, access outside the ticket,
or any write not explicitly authorized. Preserve the first transcript and
return the rig in the state required by [COORDINATION.md](COORDINATION.md).
