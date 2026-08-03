# T6040 Linux bring-up — next steps

Current as of 2026-08-03. This file states priorities and stop conditions.
Exact work items, hashes, dependencies, and approval state live in
`tickets/*.json`.

## 1. Finish the SD-root system

Ticket: **204**

The SD reader and card are already proven read/write across reboot. A 6 GiB
ext4 loop image on the card mounts, `switch_root` succeeds, and OpenRC starts.
The current failure is userspace integration: no reliable ttydc0/tty1 console
and no SSH. Corrected BusyBox `inittab`/apply files and an explicit new-root
pseudo-filesystem mount are staged offline but not yet live-proven.

Do next:

1. Exact-review the final inittab and new-root mount delta.
2. Observe one boot on the panel through `console=tty0`.
3. Keep one BusyBox console independent of OpenRC.
4. Add networking, SSH, and OpenRC services back one at a time.
5. Verify a persistent boot log changes across reboot.
6. Start Xorg and i3 only after the console and network are stable.

Use `maxcpus=1` while debugging this path. The five-core SD-root run hit a
copy-on-write fault; that is a separate kernel problem, not a userspace-service
failure.

Pass: unattended SD-root boot reaches a local console and SSH, retains a file
across reboot, and starts the graphical session without a kernel fault.

## 2. Keep the strict SD fixture sequence honest

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
changes.

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
3. **195:** test live admin traffic in m1n1 only after its artifact and plan
   satisfy the normal gate.
4. **196:** defer NVMe writes until the CQ-wrap failure is understood or
   safely avoided.

Do not revive the refuted “wrong MMIO window,” non-zero tag, batching, or
simple queue-depth explanations without new evidence.

## 4. Reframe the MM/SMP fault

Ticket 121’s old “maxcpus >= 6 initramfs-unpack threshold” wording is stale.
Later boots were non-monotonic, and the SD-root path faulted in
`copy_page → do_wp_page`. The current claim is narrower:

> Some multi-core workloads corrupt or incorrectly protect pages during copy
> or copy-on-write. Five cores are proven for the smaller RAM-root desktop, but
> full multi-core memory stability is not.

The next useful work is an offline discriminator that changes CPU topology or
memory pressure without changing drivers, storage, or boot media. Do not ship
a new threshold claim from one boot.

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
- **Audio, camera, suspend, cpuidle, backlight:** retain as roadmap work; none
  blocks the current SD-root milestone.

## Global stop conditions

Stop on an async SError, DART fault, firmware panic, unexpected reset, console
loss before the planned boundary, artifact mismatch, access outside the ticket,
or any write not explicitly authorized. Preserve the first transcript and
return the rig in the state required by [COORDINATION.md](COORDINATION.md).
