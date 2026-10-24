# Ticket 4001: read-only right-port USB block reporter for ticket 109

Claude, 2026-10-24. Offline artifact and mocked tests only. No rig, device,
mount or storage access.

```text
89b3911e2fbdde38b13b95ba0cf456ec94b9711131eb002e7d6a9df703ca9b80  scripts/t6040-usb-block-report.sh
da223657340678f551ed93750e84b360aeb74937ef592911ee9e43f92f5ebbfe  scripts/t6040-test-usb-block-report.sh
```

## Contract

`t6040-usb-block-report.sh VENDOR PRODUCT SERIAL SECTORS`. For the S128:
`0781 55fd 03043930012326064731 240328704` (host-declared values in
[the S128 identity note](2026-10-24-t6040-s128-host-declared-identity.md)).
The reporter runs these gates **before any read**:

1. No `/sys/class/nvme/*` or `/sys/block/nvme*` exists; ticket 109 asserts
   that the internal SSD is invisible.
2. Exactly one `/sys/block/sd*` has `removable=1`, the exact sector count,
   and a device path under `392280000.usb/xhci-hcd.*`. That is the right-port
   dwc3/xHCI, confirmed from the live ticket-108 boot (`io mem 0x392280000`).
   Its nearest USB ancestor must match vendor, product and serial. Zero or two
   matches stop.
3. The node is a block device; regular files are accepted only under the test
   hook.
4. Neither the disk nor any partition is in `/proc/mounts`, and nothing holds
   it (dm/md/loop).

Only after that does it read, solely through `dd if=<node> of=/dev/stdout`:
LBA 0, LBA 1–33, the last 33 sectors, and the first 8 sectors of each
partition, with starts taken from sysfs rather than parsed from the media. It
reports SHA-256 and checks byte counts, so a short read stops. It also prints
its own version and hash, the USB path and the link speed. There are no
mount, write, fsck, partition or ioctl paths.

## Tests: 19 / 19 PASS

`t6040-test-usb-block-report.sh` builds a fake sysfs tree and a regular file
standing in for the device. Cases: happy path; exact range/partition lines;
device bytes unchanged by a report; wrong serial, product, vendor, size and
controller; not removable; NVMe present; partition mounted; disk mounted;
held by dm; two matches; node missing; short device; regular file refused
outside the test hook; empty serial; bad hex. It passes under Alpine BusyBox
1.37 and under the exact initramfs BusyBox 1.35 (`61781806…`) used by the
305/109 boots.

## Still needed before 109

- Independent artifact review (non-claude).
- Packaging. The 305 initramfs (`4cc65133…`) does not contain the reporter,
  so 109 either pins this script, transferred over ttydc0 with its hash
  checked before execution, or gets a rebuilt initramfs. Both choices change
  109's exact artifacts and need review.
- The S128 is MBR+FAT32 today, so a 109 run will report the protective/legacy
  MBR plus one FAT32 partition. Expected hashes for the GPT image come only
  after ticket 110.
