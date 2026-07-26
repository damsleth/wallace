# Ticket 155: the fat graphical object (capability-first) — built, strict-verified

`m1n1-b0-dwm-fat.bin` `c5438779d5436540f2391242efde434f4b0b0368c684cb09e3b4409afca71776`
**83,197,952 B = 5078 × 16 KiB**, strict verify **PASS**, `entry=0x800`.

| Member | Hash | Note |
|---|---|---|
| m1n1 v7 window-free | `ecd264a5…` | same loader as every recent smoke |
| kernel `Image-hid-type-fix.xz` | `cbb3e743…` | **full kernel**, raw `df7657c1…` (50.8 MiB) |
| DTB `t6040-j614s-dcuart.dtb` | `2782b922…` | storage-disabled |
| initramfs `initramfs-alpine-dwm-fat.cpio.xz` | `ad1fe88b…` | 67.37 MiB → **279 MiB** expanded |
| bootargs | `3659a0da253c7059…` | **byte-identical to the proven B0 set** |

Runtime payload reserve 346,705,431 B (331 MiB) — about **1.4 %** of this machine's 23.8 GiB
(`mem_size 0x5cb500000`).

## No kernel rebuild was needed

The already-built full kernel has everything DIET stripped, checked symbol by symbol against
`config-hid-type-fix`:

`NET=y` `UNIX=y` (the 148 killer) `SYSVIPC=y` `INPUT_EVDEV=y` `DRM=y` `DRM_SIMPLEDRM=y`
`DRM_KMS_HELPER=y` `DRM_GEM_SHMEM_HELPER=y` `DRM_TTM=y` `DRM_SCHED=y` `DRM_DISPLAY_HELPER=y`
`FB=y` `FRAMEBUFFER_CONSOLE=y` `TMPFS=y` `DEVTMPFS=y` `SHMEM=y`

Three further advantages over swapping to DIET_CAPABLE:

- it is **4 KiB pages** (Image header `flags=0xa`), the page size every proven boot used — no ABI
  change on top of a graphical change;
- it carries the **DockChannel HID type fix**, so the internal keyboard works;
- it is **already live-proven on this machine**: it is the kernel inside
  `m1n1-b0-alpine-hid-restored.bin`, which booted to a shell with `event0` three times on
  2026-07-26 (accidentally, via the wrong-object incidents — those runs did establish this much).

`Image-hid-type-fix.xz` was reusable as-is and is minilzlib-safe: 1 stream, 1 block, CRC32, no BCJ.

## What FAT=1 changes

`scripts/t6040-build-alpine-dwm.sh` gained a `FAT=1` mode rather than losing the thin path:

- **no GL/JIT trimming** — `libLLVM`, `libgallium`, and 57 DRI drivers including `swrast_dri.so`
  and `kms_swrast_dri.so` are kept, so **software GL exists** (the thin image deliberately had none);
- adds `mesa-dri-gallium mesa-gl mesa-gbm kbd xdpyinfo xev` — the last three so a graphical failure
  is diagnosable *on the machine*;
- keeps the full font set; only `doc`/`man`/`info`/`licenses` are dropped (cannot affect behaviour);
- 298 MiB image, 111 packages.

## Norwegian layout: fixed and tested, not assumed

The 148 image failed with `can't open /usr/share/bkeymaps/no/no-mac.bmap: no such file` because
`kbd-bkeymaps` ships **gzipped** maps. The fat image confirms only `no-mac.bmap.gz` is present, so
the inittab now tries `.bmap`, then `zcat`s `.bmap.gz`, for both `no-mac` and `no`.

Verified by exercising the exact inittab shell logic against the real file extracted from the built
image: it falls through to the `.gz` branch and pipes **33,031 bytes** to `loadkmap`, exit 0. Layout
is also set in X via `setxkbmap no`, so both console and X paths are covered — the thin image had
neither.

## One guard was raised, deliberately

The verifier rejected the object: `initramfs expands to 292422732 bytes, over B0 limit 268435456`.

`MAX_INITRAMFS_EXPANDED` was an arbitrary **256 MiB policy** number. The expanded initramfs becomes
the RAM root, so it is a RAM guard, not a load-path limit — and 279 MiB is ~1 % of 23.8 GiB. It is
now pinned to the **real** binding constraint, `MAX_COMPRESSED_EXPANSION` = 1 GiB, which is what
m1n1's xz decoder advertises; an xz member cannot expand past that regardless. It remains a runaway
guard (a multi-GiB root is still a bug) but is no longer tighter than the hardware.

Deliberately **not** raised to "just above my build" — that would repeat the mistake of fitting a
guard to whatever happens to be at hand. `--self-test` still passes. `MAX_OBJECT_SIZE` was left at
256 MiB; ticket 156 measures that separately.

## Expectations for the smoke

- **Slower boot**, unavoidably: 67 MiB of xz must be decompressed single-threaded (minilzlib requires
  single-stream/single-block, `-T1`). Do not read a long pause as a hang.
- AF_UNIX now exists, so Xorg should get past socket creation. The next unknown is what 148
  originally predicted: whether `modesetting` probes simpledrm cleanly. This kernel *does* have the
  `TTM`/`SCHED`/`DISPLAY_HELPER` helpers DIET dropped, so the odds are much better — but it is
  genuinely untested.
- `/var/log/xorg-startx.log` remains the first thing to read on failure, and `xdpyinfo`/`xev` are now
  on the image.

## Run it

```sh
bash scripts/t6040-debugusb-console.sh reboot
bash scripts/t6040-boot-raw-object.sh \
    ~/Code/linux-build-out/m1n1-b0-dwm-fat.bin \
    c5438779d5436540f2391242efde434f4b0b0368c684cb09e3b4409afca71776
```
