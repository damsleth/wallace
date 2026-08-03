# T6040 J614s trackpad motion exact-artifact cross-review

Date: 2026-07-24
Rig ticket: 004
Verdict: **NO-GO; exact candidate retired unrun**

## Exact bytes reviewed

The reviewer reproduced and matched the ticket's m1n1, Image, DTB, initramfs,
paired HIDF firmware, second-build duplicates, embedded init, and storage
disablement. The initramfs has no device nodes, the bounded reporter does not
depend on ttydc0 RX, and the MTP/HID channel is the previously live-proven
IRQ-backed path. No USB, storage, PCIe, SPMI, PMU, charger, NVRAM, unknown
MMIO, or GPIO reset implementation is present.

## Functional blocker

The exact Image `86e031db...` cannot meet the ticket's registration or motion
conditions:

- `apple_dockchannel_hid.c` never sets `hid->type`;
- `CONFIG_HID_APPLE=y` claims the Apple BUS_HOST wildcard match, then rejects
  `HID_TYPE_OTHER`, which is the already-proven ticket-076/077 failure;
- `CONFIG_HID_MULTITOUCH=m`, but the initramfs contains no modules and its init
  never loads one;
- consequently no multi-touch event node can bind, and the reporter cannot
  open it to invoke the firmware/start path.

The replacement must apply `patches/t6040-dockchannel-hid-type.patch`, set
`CONFIG_HID_MULTITOUCH=y`, rebuild twice, pin every new hash, and receive a new
independent exact-artifact review. The build harness now has a gated
`TRACKPAD_MOTION=1` mode that requires `DOCKCHANNEL=1`,
`HID_TYPE_FIX=1`, and a storage-disabled build.

## Firmware-policy gate

This path does not flash firmware or touch persistent NVM. It does, however,
copy the exact 79,928-byte paired HIDF payload into volatile coherent DMA and
send the known runtime firmware and interface-reset commands. That is not
literally read-only hardware and the unqualified project rule still says
“Never write firmware.”

A future live ticket therefore needs an explicit maintainer-recorded exception
for this exact volatile, paired, non-persistent runtime upload. That exception
does not authorize flash/NVM writes, arbitrary firmware, another board's blob,
GPIO/PMU reset, or any other write. Until both the rebuilt-artifact review and
that policy acknowledgment exist, do not run a trackpad motion experiment.

The maintainer must also be present to provide finger motion during the bounded
capture. The healthy `Running proxy` state was not consumed.

## Superseding result

Offline ticket 125 subsequently made exactly those two corrections, reproduced
the resulting artifacts twice, and passed independent exact-artifact review.
Its authoritative manifest is
`evidence/2026-07-24-t6040-trackpad-motion-revised-preflight.md`. Live ticket 126
remains proposed and unapproved under the firmware-policy and attendance gates
above.
