# T6040 bootable-build experiment ladder

Date: 2026-07-24

Current state: the tethered B0 release-object proof passed (tickets 081/100).
The remaining B0 boundary is approved ticket 101's maintainer-executed
enrolled cold boot, after ticket 082's exact volume identity/backup fields,
dual-mode-object review/trigger validation, and the current rig recovery gate.

## Target milestone

The nearest honest “bootable Linux build” milestone is:

> From the Apple boot picker, select the dedicated m1n1 volume and reach an
> Alpine login on the internal display, using the internal keyboard, without a
> host uploading m1n1, Linux, the DTB, or initramfs.

The first version may be entirely RAM-resident. It does not claim persistent
Linux storage, internal NVMe, USB host, accelerated graphics, or a standard EFI
boot flow. That separation matters:

1. **B0 — untethered RAM distro:** enrolled raw m1n1 boot object carries a
   self-contained kernel, J614s DTB, and Alpine initramfs. This is the immediate
   target.
2. **B1 — standard boot flow:** m1n1 starts U-Boot, then EFI GRUB/systemd-boot
   or a unified kernel image. This follows B0 rather than blocking it.
3. **B2 — persistent distro root:** switch to external USB root once the
   T6040 HPM/ATC physical-link path works, or to internal NVMe only if the SPTM
   boundary gains a supported solution.

The DebugUSB/KIS tether may remain attached for observation during B0 testing,
but it must not deliver any payload or command needed for success.

## Rules shared by every live experiment

- A live step gets its own exact hashes, independent review, preflight, rig
  ticket, explicit maintainer approval, and lease.
- Change one boundary at a time. Do not combine HID repair, SMP, cpufreq, USB,
  PCIe, U-Boot, or enrollment in one first run.
- Keep `maxcpus=1 idle=nop` through the B0 milestone. SMP and cpufreq have
  separate approved gates.
- The first B0 images keep all USB/DART/ANS/SART/NVMe nodes disabled.
- Never write PMU/charger/NVRAM/firmware, unknown SPMI endpoints, or invent
  MMIO offsets. A non-PMU SPMI transaction is allowed only as its own exact
  staged experiment under `docs/SPMI_SAFETY.md`; it must never be smuggled
  into a B0 image.
- Enrollment is a separate, explicitly approved action with a known-good
  rollback boot volume. No offline ticket authorizes `kmutil`, `bputil`, APFS,
  or Boot Policy changes.
- Stop and recover on async SError, DART fault, reset/watchdog loop, unexpected
  storage/USB probe, missing output boundary, or any artifact mismatch.

## Experiment 1 — capture the current HID failure boundary

Ticket: **076**, completed.

Boot ticket 074’s exact observation-only kernel and storage-disabled DT with
ticket 075’s TX-only auto-reporter. Send no target command. Capture the bounded
report and recover after its end marker.

Pass is evidence, not necessarily working HID: the report must locate the
furthest reached DockChannel/DCHID state and inventory input devices without
depending on ttydc0 RX. The captured report led directly to 077/078.

## Experiment 2 — turn the trace into one minimal hypothesis

Ticket: **077**, completed offline.

Apply the interpretation matrix from ticket 074’s trace preflight to the exact
ticket 076 report:

- no UART/DockChannel RX activity;
- DockChannel bytes without DCHID callback;
- parsed packets without comm events;
- INIT/READY/identity mismatch;
- successful identity but failed interface creation.

Produce a count-by-count evidence table and compare it to the working
2026-07-11 kernel. If one boundary is supported, draft the smallest possible
change and an observation-only regression check. If the report is
insufficient, specify one additional counter/log at the demonstrated boundary.
Do not guess a receive kick, retry, new MMIO access, or IRQ change.

Exit: a reviewable patch or a narrowly justified next observation patch, plus
an exact statement of what result would falsify it.

Result 2026-07-24: the trace reaches every `hid_add_device()` return with zero,
but that only proves `device_add()`. Ticket 077 found the causal surrounding
delta: Asahi's wildcard BUS_HOST `hid-apple` rejects the active transport's
unset `hid->type`, while `hid-generic` declines because a special driver
matched. Ticket 078 copies the sibling driver's keyboard/mouse type assignment;
the exact live candidate registers `input0/event0` with empty partitions.

## Experiment 3 — build a HID-restored Alpine candidate

Ticket: **078**, completed.

Build the minimal ticket-077 candidate against the same config and
storage-disabled DT. Extend the automatic report with only:

- `/proc/bus/input/devices`;
- `/dev/input` inventory;
- a bounded read-only event capability listing if an input node exists.

Do not require ttydc0 RX and do not inject input. Host-test the report, verify
the patch contains no new hardware address or forbidden accessor, build twice,
hash everything, and obtain independent review.

Only after that work may a separate one-shot rig ticket be proposed. Its pass
condition is internal keyboard registration while Alpine, watchdog, ttydc0 TX,
and the empty partition inventory remain healthy. A failed hypothesis returns
to experiment 2; it does not authorize iterative live poking.

## Experiment 4 — make a release-like RAM distro bundle

Ticket: **079**, completed offline.

Turn the diagnostic minirootfs into a reproducible Alpine B0 image:

- pin the Alpine repository snapshot and every installed package;
- use normal Alpine/OpenRC userspace rather than a respawning debug shell;
- keep a framebuffer login and ttydc0 output path;
- include watchdog keepalive and a bounded boot-health report;
- carry no block-device node, storage auto-discovery, network configuration,
  SSH key, password, or machine-specific secret;
- keep USB, ANS, SART, and NVMe disabled in the paired DT;
- record compressed/uncompressed size and the complete package/file manifest.

Host validation must boot the userspace in an arm64 container/chroot far enough
to check init syntax, service ordering, console configuration, ownership,
reproducibility, and absence of block nodes. This creates the distro artifact;
it is not yet an enrolled boot object.

Exit: a versioned `m1n1 + Image + DTB + Alpine initramfs` manifest whose Linux
payload has already passed a tethered one-shot boot with internal keyboard,
simpledrm/fbcon, watchdog, and no unexpected storage probe.

## Experiment 5 — audit the raw boot-object payload contract

Ticket: **080**, completed offline 2026-07-23.

Resolve how the already-enrolled raw m1n1 object can carry or locate the three
Linux payloads without `linux.py`:

- identify the exact m1n1 payload/container format, magic, alignment, load
  addresses, compression support, and autoboot selection;
- derive maximum safe object and payload sizes from source and the current
  memory map, including display/log carveouts and initramfs expansion;
- confirm the raw entry point remains `2048` and no Mach-O/SPTM path is used;
- build a host parser that rejects overlap, truncation, wrong hashes, and a
  missing payload;
- document whether direct m1n1 payloads reach B0 sooner than U-Boot.

No APFS volume, Boot Policy, or enrolled object is read or changed in this
experiment. If m1n1 cannot directly package all three payloads, the output is a
precise requirement for ticket 025’s U-Boot/FIT route.

Exit: a byte-level layout specification, verifier, size budget, and selected
direct-m1n1 or U-Boot route.

Result: direct raw m1n1 is sufficient for B0. The object is the exact raw
m1n1 prefix followed by `chosen.bootargs`, compressed kernel, raw DTB,
compressed initramfs, and a zero terminator. The raw entry remains `0x800`;
Wallace applies a conservative 64 MiB complete-object policy and exact
component/expansion verification. Full contract:
`done/2026-07-23-t6040-raw-boot-object-layout.md`. Host gate:
`scripts/t6040-raw-object-verify.py`.

Ticket 081 used independently reviewed, PCIe-write-free m1n1 `1394c345...`,
reverified every final byte, and passed the tethered proof under ticket 100.

## Experiment 6 — build and tether-test one self-contained raw object

Tickets: **081**, completed offline; live proof **100**, completed.

Construct one raw object containing the exact B0 m1n1, kernel, DTB, and Alpine
image. Reparse it with the experiment-5 verifier and independently review its
source hashes, offsets, entry point, expansion bounds, and expected command
line.

The live test chainloaded only this single object over KIS.
It must not run `linux.py` or upload a second payload. Success means the object
autodiscovers its embedded payload and reaches the already-proven B0 Alpine
acceptance state. KIS is observational only after chainload.

Ticket 100 was the exact reviewed one-shot rig ticket and passed.

Ticket 079's release userspace and the exact ticket-081 object candidate now
exist. `initramfs-alpine-b0.cpio.gz` (`ddd981711e91...`) and
`m1n1-b0-alpine-openrc.bin` (`2371ee5dfbfa...`) each reproduce byte-for-byte;
the latter strictly decodes to safe m1n1 + the ticket-078 kernel + unchanged
storage-disabled DTB + the OpenRC root. Result and hashes:
`done/2026-07-24-t6040-alpine-b0-release-bundle.md`. Independent review
reproduced it, and ticket 100 reached OpenRC default runlevel, watchdog, panel
shell, `input0/event0`, empty partitions, and local keyboard echo. The exact
procedure and review checklist are in
`done/2026-07-24-t6040-alpine-openrc-single-object-preflight.md`.

An earlier delivery-only control is now available without weakening that gate.
`m1n1-b0-alpine-hid-restored.bin` (`b50f52ab1fac...`) packages the exact
ticket-078 live-proven Alpine components behind safe m1n1 and passes strict
offset/hash/expansion checks twice. Completed ticket 089 uploaded only this
object, invokes no `linux.py`, and expects the existing ttydc0 automatic report
plus `event0`. It de-risked embedded autoboot before ticket 100 separately
closed the release-object proof.

## Experiment 7 — prepare the reversible enrolled cold boot

Ticket: **082**, procedure prepared after the successful single-object test.
Approved live ticket: **101**. Ticket 026's installer notes may inform it but
do not block the manual B0 path.

The procedure now contains:

- exact `kmutil configure-boot --raw` invocation and verified raw entry point;
- target-volume identity checks that make selecting the main macOS volume
  impossible;
- current enrolled-object backup/hash procedure;
- boot-picker cold-boot steps;
- an observation-only KIS capture that supplies no payload;
- recovery and rollback from 1TR or the main macOS volume;
- pass/stop conditions for one cold boot.

Remaining before execution: fill the dedicated volume UUID, back up and hash
the currently enrolled object, independently review dual-mode candidate
`46237ade...` under ticket 119, validate its normal/debug trigger distinction, decide whether
enrollment and boot use split approvals, and recover the current wedged KIS
link. The agent does not execute `kmutil` or change Boot Policy; the maintainer
performs enrollment.

Enrollment and boot remain separate actions if the maintainer wants that split.
The live pass condition is boot picker → m1n1 → Linux → Alpine login with
simpledrm/fbcon, internal keyboard, watchdog, and no host payload transfer.
That is milestone B0. Exact procedure:
`done/2026-07-24-t6040-b0-enrolled-cold-boot-preflight.md`.

## After B0

- Ticket 025's offline B1 preparation is complete: a reproducible
  framebuffer-only T6040 U-Boot target maps no MMIO, compiles a built-in EFI
  hello test, and has no autoboot or bus drivers. Test it only after B0 as a
  separately reviewed payload; do not make EFI a prerequisite for the first
  cold boot. Result: `done/2026-07-23-t6040-uboot-noio-prep.md`.
- Tickets 096–099 and the decomposed link/block/flash/root experiments are the
  B2 external-root path. Right HPM2 now reaches S0 and image 098 is ready, but
  role/VBUS/ATC, child enumeration, block access, flashing, and writes remain.
- Ticket 030's paired 25F84 restore corpus is complete and can be supplied to
  later rootfs/initramfs builds. Its missing machine-private ALS calibration
  is ticket 087 and does not block B0 or B2 root mounting.
- Internal NVMe remains behind the documented SPTM/CoastGuard boundary.
  Tickets 051/052/054/055 are research, not a near-term boot dependency.
- SMP, cpufreq, PCIe/WiFi, trackpad firmware, SMC, GPU, audio, and suspend are
  post-B0 enablement lanes. None should be folded into the cold-boot proof.

## Dependency graph

```text
076 trace capture
  -> 077 boundary decode
       -> 078 HID-restored candidate
            -> 079 release-like RAM distro
                 -> 081 self-contained raw object
                      -> 100 reviewed tethered single-object boot PASS
                           -> 082 identity/backup + dual-mode review
                                -> 101 enrolled cold boot (approved)
                                     -> B0

024 interim path -> 080 raw-object layout audit --------^
026 enrollment notes (informational, not a B0 gate) ----^

B0 -> 025 U-Boot/EFI (B1)
B0 + reviewed HPM/ATC -> enumeration -> block read -> flash -> USB root (B2)
```
