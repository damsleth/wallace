# T6040 SD root: working at one core, integrity hardening pending

Date: 2026-08-03

Ticket: 204

Result: **PARTIAL PASS** — the root path works at `maxcpus=1`; the fixture is
currently dirty and must not be mounted read/write before ticket 215.

## Proven path

The existing `SD64` exFAT partition was not repartitioned or reformatted. It
contains `wallace-root.img`, a 6 GiB ext4 filesystem used as `/`:

```text
GL9755 -> mmcblk0p1 (SD64, exFAT) -> wallace-root.img -> loop0 (ext4) -> /
```

At `maxcpus=1`, the system reached:

```text
sdroot: newroot /dev ok (ttydc0 present)
sdroot: switching to the SD root
OpenRC 0.63.2 is starting up Linux 7.1.3 (aarch64)
hostname: t6040
root: /dev/loop0, 5.8 GiB, about 371 MiB used
```

`/root/boot-log.txt` contained two different boot timestamps, proving that the
ext4 image persisted writes across reboot. DockChannel console, OpenRC, D-Bus,
and Bluetooth started in the successful one-core boot.

The rotating `dcuart-console.log` was later overwritten by SMP testing. The
committed excerpt above remains, but there is no preserved, hash-pinned full
transcript for that successful boot. Future tickets must use unique log names.

## SMP boundary

The same small root fails with more than one CPU. Ticket 205 reduced this to a
general MM/copy-on-write fault:

| CPUs | Result |
|---|---|
| 1 | clean repeated boot and shell |
| 2 | non-init processes fault in kernel page-copy paths |
| 3 or more | PID 1 commonly faults and the kernel panics |

This is not specific to initramfs size or SD storage. Use `maxcpus=1` for the
SD-root acceptance path until ticket 205 is resolved.

## Integrity problem found during review

Later panic-driven runs recorded both:

```text
exFAT-fs (mmcblk0p1): Volume was not properly unmounted
EXT4-fs (loop0): recovery complete
```

The original design mounted the outer exFAT filesystem and the loop ext4 root
read/write but had no way to detach them before reboot. Ticket 204 is therefore
not complete, despite the successful userspace boot.

No further SD-root read/write mount is permitted until ticket 215 runs the
reviewed automatic-only repair and repeats read-only checks for both
filesystems.

## Hardened candidate

The offline replacement adds:

- exact `LABEL=SD64`, exFAT type, image-size, and ext4-UUID checks;
- direct exFAT and ext4 clean-state checks before any read/write mount;
- fatal handling for mount, pseudo-filesystem, tty, and root-identity failures;
- a DockChannel console started before blocking OpenRC work;
- diagnostic `sdroot.shell` mode that keeps BusyBox init as PID 1;
- a shutdown tmpfs and BusyBox `restart` action that pivots away from the ext4
  root, unmounts it, detaches the loop, unmounts exFAT, then powers off.
- a repair image stripped of standalone partitioning, formatting, resize,
  label, discard, and PCI-configuration tools outside the ticket's scope.

Two clean initramfs builds were byte-identical.

| Artifact | SHA-256 |
|---|---|
| `m1n1-sdroot-hardened.bin` | `97a304880e35e268e846273c23ed38bddf1a837ca431590a855e03e56d5e8c9f` |
| `Image-sdroot-hardened` | `bcc1ea09479f89e1dbf286721b62a7c89e147385362d3c496cf05b25168118c4` |
| kernel config | `96e83d858ddbbcf19027d3ea56411158f75ae75fe4c42c0b03dbdd28b6da3eee` |
| hardened DTB | `879caa5abc565977315ec1b359174307efa10e7769676258a5a7eb19e6f3e1e5` |
| hardened initramfs | `a412a2841f0b995ec6cf7f0a09a14c2fee5f4f69873bde902ada40b8ba02c6d3` |
| repair initramfs | `71b725dc1e3eb17a4d5eb22b6adcffdabfa123c2725ec38c6e30848aacfeae1b` |

The config has `MMC`, `MMC_BLOCK`, `MMC_SDHCI`, `MMC_SDHCI_PCI`, `EXFAT_FS`,
`VFAT_FS`, `EXT4_FS`, `BLK_DEV_LOOP`, and `TMPFS` built in.
The initramfs carries BusyBox `mount`, `umount`, `ls`, `findfs`, `blkid`,
`losetup`, `sha256sum`, and the other ticket commands; the repair image adds
only the pinned `fsck.exfat` implementation needed beyond the existing
`e2fsck` path.

## Stop and next

1. Ticket 215: independently review, repair, and recheck SD64 and the ext4 image.
2. Ticket 216: apply the root configuration, boot at one core, exercise the
   clean shutdown pivot, then prove both filesystems remain clean.
3. Close ticket 204 only after ticket 216 passes with a uniquely named,
   hash-pinned transcript.

No new SMC key, SPMI, PMU, charger, NVRAM, firmware, repartition, or reformat is
part of either candidate.

## Flagged follow-on: untethered stage 2

Do not build this yet. U-Boot already has Apple PCIe and generic PCI SDHCI
support, so the GL9755 could plausibly hold an untethered stage-2 object, but
U-Boot cannot read the card's existing exFAT filesystem. That route would need
a separate FAT32 partition and therefore an explicitly approved repartition.
It also duplicates the internal-NVMe stage-2 design in tickets 190/191. SD is
the simpler removable recovery medium; NVMe is the cleaner permanent path if
its Linux/firmware handoff and integrity model can be made reliable.
