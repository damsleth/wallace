# T6040 Alpine external-root image

Date: 2026-07-24  
Ticket: 086  
Scope: host-only; no block device, rig, SPMI, PMU, HPM, or Boot Policy access

## Result

A flash-ready 1 GiB raw disk image now exists outside the repository:

| Item | Identity |
|---|---|
| image | `/Users/damsleth/Code/linux-build-out/t6040-alpine-usb-root.img` |
| size | 1,073,741,824 bytes |
| SHA-256 | `32a897cb48bab0f066528b76cc6ef6b364a2807b43371d5b2f3c2abcced42cd1` |
| disk GUID | `4d26d3d2-96d8-4814-b32e-184b053505cc` |
| partition GUID / PARTUUID | `1b841e9b-65a5-4687-83f2-6c728961ad14` |
| ext4 UUID | `6831bf2b-06cf-40c9-9e86-39ddb792ba18` |
| label | `t6040root` |
| manifest | `/Users/damsleth/Code/linux-build-out/t6040-alpine-usb-root.manifest` |

The matching boot selector is:

```text
root=PARTUUID=1b841e9b-65a5-4687-83f2-6c728961ad14 rootfstype=ext4 rootwait
```

The root is the pinned Alpine 3.24.0 aarch64 minirootfs
(`4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a`).
It adds an automatic no-login `/bin/sh` getty on `ttydc0`, so a successful
`switch_root` remains observable without relying on the currently regressed
internal keyboard receive path. The image intentionally has empty modules and
firmware trees. The paired USB-root kernel has all boot-critical components
built in: ext4, SCSI disk, USB storage/UAS, xHCI, DWC3, and Apple DART.

## Builder and verification

`scripts/t6040-build-usb-root-image.sh` creates a regular file only. It refuses
existing outputs, stages the root with the guarded population tool, then uses
an isolated Linux container to create GPT and ext4 without mounting anything.
It runs:

- `e2fsck -fn` on the populated ext4 filesystem;
- `sgdisk -v` on the completed raw image;
- `sgdisk -i 1` to confirm the type, exact PARTUUID, extent, and label;
- SHA-256 over the final image.

The existing host tests now also require the `ttydc0` getty. Shell syntax,
population tests, GPT validation, and ext4 validation pass. No real disk was
opened by either builder.

## Exact paired boot artifacts

These remain the live-proven, right-port-only set:

| Artifact | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-usb-host` | `6f0daf57baf942d6e1f43d8efa2ebd4160e976c02ccfaad232dd42e918eb7482` |
| `t6040-j614s-dcuart-usb-host-right.dtb` | `9bee944b8bb0d6d7ab541962ea2edc9a57c4069fedcd6c32db21e3b824a43759` |
| `initramfs-usb-root.cpio.gz` | `8b9b80c4eaad07aa0efa578a827f9d0766be81e9a4aed2650e748b1fc65993c8` |

The root-mode command line is the already-reviewed single-core USB command
line plus the `root=PARTUUID=... rootfstype=ext4 rootwait` selector above.

## What is and is not unblocked

The image is ready to flash as soon as the stick is attached to the M1 and its
exact removable whole-disk node is reviewed. The current attachment is to the
M4, so `diskutil list external physical` on the M1 correctly shows no target.
No flash has occurred.

The M4-side gate is unchanged. Ticket 063 already tested this bus-powered
USB-C stick on the right port: T6040 DART and xHCI root hubs initialized, but no
child or `sd*` appeared. Current m1n1 detects the M3/M4 SPMI layout but
deliberately skips the HPM controller and only powers the PHY blocks. Linux
likewise lacks the T6040 SN201202x/SPMI role-orientation and ATC PHY provider.
Repeating the same attached-at-boot topology cannot prove anything new.

Do not guess or replay SPMI/HPM writes. The next M4 root-mode boot requires
either:

1. a standards-compliant powered/self-powered fixture that makes a child
   persist for ten seconds, or
2. reviewed T6040 SPMI + SN201202x/HPM + ATC PHY support derived from the
   paired driver/ADT and accepted under the hardware-write safety process.

Untethered boot is a separate layer: Apple Boot Policy starts an internally
enrolled raw m1n1 object, which then loads this external root. The USB stick is
not directly bootable by Apple firmware. A root-mode self-contained object can
be packaged and enrolled only after the host link enumerates and after the
usual exact-hash, review, approval, rollback, and cold-boot gates.

## Flash boundary

When the stick is moved to the M1:

1. record `diskutil list external physical` and `diskutil info` before and
   after insertion;
2. confirm the exact whole disk is external, removable, writable, and not the
   M1 system disk;
3. unmount that exact disk;
4. verify the source image SHA-256 above;
5. write only after explicit confirmation of the resolved `/dev/diskN`;
6. read back the GPT header and a full-device/source hash where practical.

The image builder does not implement flashing. That destructive step stays
deliberately separate from artifact creation.
