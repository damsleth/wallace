# T6040 Alpine/OpenRC persistent-root image

Date: 2026-07-24
Ticket: 098
Scope: host regular files only; no block device, mount, rig, SPMI, or Boot
Policy access

## Result

The release-qualified Alpine/OpenRC B0 root now has a flash-ready 1 GiB
GPT/ext4 image:

| Item | Identity |
|---|---|
| image | `/Users/damsleth/Code/linux-build-out/t6040-alpine-openrc-usb-root.build4.img` |
| image SHA-256 | `1c493fad1d1b44520d9265c5946c8ac00b867b3d47fac93f88d1f55cde25060e` |
| manifest SHA-256 | `a73369344b66011306397dcb5c61ae152c0f2dd62b9b8a0dd0e6ec04b8247d8e` |
| disk GUID | `192409a8-fe11-4cbf-9182-14eb737b69a6` |
| partition GUID / PARTUUID | `e4731abe-3566-4c3a-8019-c8828ca27a5a` |
| ext4 UUID | `912d5c4e-7475-4875-a178-52ce5119a703` |
| label | `t6040root` |
| normalized tree manifest | `/Users/damsleth/Code/linux-build-out/t6040-alpine-openrc-usb-root.tree-manifest` |
| normalized tree SHA-256 | `04ddd68e63a782572d3f07be57322f81ee1586cb2cf6c18775aa9e59e16a2acd` |

The required boot selector is:

```text
root=PARTUUID=e4731abe-3566-4c3a-8019-c8828ca27a5a rootfstype=ext4 rootwait
```

The root source is the verified
`initramfs-alpine-b0.cpio.gz`
(`ddd981711e91c917b735d39df0e90dd50200c158e1ea54c7f2c171c8ad317024`).
The image contains executable aarch64 OpenRC and `openrc-run`; its inittab
runs the normal `sysinit`, `boot`, `default`, and shutdown paths. The default
runlevel enables the bounded health reporter and watchdog service. It has one
delayed DockChannel `ttydc0` console and the framebuffer tty0 autologin, with
no network runlevel.

The exact PARTUUID is recorded in GPT, `/etc/fstab`,
`/etc/wallace-root-partuuid`, and the manifest. The paired firmware manifest
contains 22 files from the restore-recoverable 25F84 J614s tree. The modules
manifest is intentionally empty because the selected boot kernel has ext4,
SCSI disk, USB storage/UAS, xHCI, DWC3, and Apple DART built in.

## Validation

Independent regular-file inspection passed:

- primary and backup GPT header and partition-array CRCs;
- protective MBR, Linux filesystem type, exact partition extent, label, disk
  GUID, and PARTUUID;
- `e2fsck -fn`, ext4 label/UUID, and clean filesystem state;
- independent `debugfs rdump` extraction and normalized 727-line tree
  manifest;
- executable OpenRC/OpenRC-run, complete inittab/runlevels, health reporter,
  watchdog, console, PARTUUID, firmware, and empty-module contracts;
- shell syntax, population tests, and absence of block/special nodes.

No real disk was opened. Flashing remains ticket 099's separately confirmed
whole-device operation.

## Reproducibility boundary

Builds 3 and 4 used the same fixed GUIDs and inputs. Their normalized
path/mode/link/content manifests are byte-identical with SHA-256
`04ddd68e63a782572d3f07be57322f81ee1586cb2cf6c18775aa9e59e16a2acd`.
The raw images are not byte-identical:

- build 3 SHA-256:
  `8003c88ea0725f9a33297d6253d53eb3b8fdca9307c5a0c77302bf191ffa182d`;
- build 4 SHA-256:
  `1c493fad1d1b44520d9265c5946c8ac00b867b3d47fac93f88d1f55cde25060e`;
- exactly 3,625 bytes differ, all within the group-0 inode table;
- the 725 imported inodes 13 through 737 differ only at inode offset 12
  (`i_ctime`) and checksum bytes 124/125 and 130/131;
- build-3 ctime is `1784924754`, build-4 ctime is `1784924785`, exactly the
  31-second build separation;
- no byte outside the inode table differs.

`E2FSPROGS_FAKE_TIME=1` fixes the superblock timestamps, but `mkfs.ext4 -d`
still assigns imported inode ctimes from wall clock and updates the associated
metadata checksums. Ticket 098 therefore qualifies the byte-identical
normalized filesystem tree and records this fully isolated e2fsprogs
nondeterminism; it does not claim a reproducible raw-image hash.

## Builder closure

`scripts/t6040-build-usb-root-image.sh` now defaults to the verified
Alpine/OpenRC B0 archive and its exact hash. It refuses to continue unless the
staged root has executable OpenRC/OpenRC-run, the OpenRC sysinit/default
inittab actions, and the exact default-runlevel watchdog and health-service
links. The generic population helper retains minirootfs support for its
historical unit test, but the flash-image builder can no longer silently
recreate ticket 086's nonbootable root.

## Independent review

Result: **PASS**. The reviewer verified the canonical image, manifest, tree
hash, exact GUIDs, OpenRC root hash, and every documented inode-table
difference. A minirootfs override failed closed on missing `/sbin/openrc`
before creating an image or manifest. A repacked B0 archive missing the health
runlevel link likewise failed closed before image creation. The normal host
test suite, shell syntax, and diff checks pass. No rig, mount, or block device
was touched.
