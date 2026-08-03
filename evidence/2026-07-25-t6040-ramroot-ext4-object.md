# T6040 root=/dev/ram0 ext4 rehearsal object (ticket 145) — built (2026-07-25)

Purpose: exercise the **real root path** — `root=`, a genuine block device, `fstab`, OpenRC on
a mounted filesystem, `e2fsck` — *before* USB storage exists, so that when enumeration finally
lands (096/097/128) the software side is already proven instead of debugging two unknowns at
once. Directly de-risks tickets 099/112/113.

## Artifacts

```text
ramroot-alpine-b0.ext4        4e589df0bfcd024ad5a3f09a20eb63e4f937bc7b40a975deb88ac003752a9fbc
                              67,108,864 B (64 MiB), label t6040root,
                              UUID e442113d-9bc9-499c-a85f-195209544298, e2fsck clean
m1n1-b0-ramroot-ext4.bin      ec111c6dffff6928645157f9cda95238d4cd71b9370d6064f32c55d53da869cc
                              78,594,048 B (74.95 MiB) = 4797 x 16 KiB pages
```

Members: window-free m1n1 v7 `ecd264a5`, **`DIET_CAPABLE` kernel** `Image-b0-dietcap.xz`
(needed for `BLK_DEV_RAM` + `EXT4`), storage-disabled DTB `2782b922`, and the ext4 image
carried as an `m1n1-wrapper` record. Bootargs:
`… root=/dev/ram0 rw ramdisk_size=65536`.

## How a filesystem image gets to be the root

m1n1 has no notion of a disk, but it does not need one:

- `src/payload.c` recognises an `m1n1_initramfs` + LE32-size wrapper and passes it to
  `load_cpio()`, which performs **no content validation at all** — it simply calls
  `kboot_set_initrd(p, size)`.
- So an arbitrary blob can be handed to Linux as an **initrd**. With `CONFIG_BLK_DEV_RAM`,
  a non-cpio initrd is loaded into `/dev/ram0`, and `root=/dev/ram0` mounts it.

`scripts/t6040-build-raw-object.py` gained `--initrd-wrapped` for this (the wrapper carries an
explicit size, so the blob must be uncompressed — hence the 64 MiB member and 75 MiB object,
comfortably inside the ≥256 MiB proven load ceiling).

Verified in the built object: wrapper at `0xaf3543`, declared size exactly 67,108,864, blob
byte-identical to the image, ext4 superblock magic `53ef` at `+0x438`, label `t6040root`.

## The verifier keeps its teeth

`t6040-raw-object-verify.py` rightly rejected this object at first — it enforces that a wrapped
initramfs is a newc/crc cpio. Rather than weaken that, it now takes `--initrd-fs-image`, which
accepts a wrapped payload **only** if it looks like an ext2/3/4 superblock. Behaviour:

| Invocation | Result |
|---|---|
| default | `FAIL: wrapped initramfs is not a newc/crc cpio archive (pass --initrd-fs-image if it is deliberately a filesystem image)` |
| `--initrd-fs-image` | `PASS`, record typed `m1n1-wrapper` |
| `--self-test` | `PASS` |

So a genuinely malformed initramfs still fails by default; only this deliberate shape is
allowed, and only when asked for.

## What the boot should prove

The image carries an OpenRC service `t6040-root-report` that prints to the console:

- the root device and filesystem type from `/proc/mounts` (expect `/dev/ram0 ext4`);
- `/proc/partitions` — expect `ram0` present, i.e. a **real block device**, not a tmpfs
  pretending to be one;
- a write test on the mounted root (expect `root is WRITABLE`);
- the Norwegian keymap status.

Plus `fstab` is real (`/dev/ram0 / ext4 rw,relatime 0 1`) rather than the empty file the
initramfs RAM-root ships.

## Not yet booted

Needs a tethered chainload smoke over **KIS** (the USB gadget cannot observe a `tty0`
console — see the harness rule in `evidence/2026-07-25-t6040-ubuntu-untethered-object.md`), which
in turn needs a proxy-capable object enrolled. **Also note this is the first use of the
`DIET_CAPABLE` kernel, which is 16 KiB pages where the proven B0 kernel is 4 KiB** — an
ABI-level difference, so a failure here could be the page size rather than the root path. If it
misbehaves, retest the same ext4 object against a 4K `BLK_DEV_RAM`-enabled kernel to separate
the two variables.
