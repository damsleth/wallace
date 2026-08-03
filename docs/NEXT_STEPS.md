# T6040 Linux bring-up — next steps

Current as of 2026-08-03. This file states priorities and stop conditions.
Exact work items, hashes, dependencies, and approval state live in
`tickets/*.json`.

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

## 5. Resolve trackpad initialization

The exact J614s HIDF upload command returned success. The following
`CMD_RESET_INTERFACE(0)` returned `kIOReturnBadArgument`. This is not an
upload crash and does not prove that the firmware consumed every byte.

Next work is protocol analysis of the expected post-upload reset state and
interface number. Any new live attempt remains limited to the already approved
volatile HIDF blob and requires its own reviewed ticket.

## 6. Parked tracks

- **USB host/VBUS:** the current SN201202x transport is an offline lead, not a
  proven power-role implementation. R3 remains no-go pending reversible
  primary evidence.
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
