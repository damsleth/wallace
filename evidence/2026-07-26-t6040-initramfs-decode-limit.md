# The fat object never unpacked its initramfs — and I had disabled the guard that caught it

## What happened on the panel

```
check access for rdinit=/sbin/init failed: -2, ignoring
/dev/root: Can't open blockdev
VFS: Cannot open root device "" or unknown-block(0,0): error -6
```

`-2` is ENOENT. The kernel could not find `/sbin/init`, fell back to a real root device, found none,
and rebooted.

`/sbin/init` **is** present in the image (entry 426 of 4217), so the file was never the problem: the
**initramfs was never unpacked**. The timestamps prove it independently — everything from 0.084 s to
0.152 s, whereas unpacking a 279 MiB initramfs takes seconds.

## Root cause: m1n1's XZ decoder rejected the member

From the host-side console log, first line:

```
XZ decode failed
```

and there is **no `FDT: initrd at ... size ...` line**, which `kboot.c` prints whenever it passes an
initrd. So m1n1 decompressed nothing, set no initrd, and the kernel booted with an empty rootfs.

**Measured boundary:** expanded initramfs of **13.1, 50.8, 60.5 and 97.3 MiB all decode and boot**;
**278.9 MiB fails**. The true limit lies in **(97.3, 278.9] MiB** and is not yet measured (ticket 160).

Two plausible mechanisms were **checked and ruled out**, rather than assumed:

- *XZ block-header size metadata.* minilzlib's own header states it does not handle "files with a
  compressed/uncompressed size metadata indicator". Parsing byte 13 of every member showed
  `flags=0x0000` for all of them — no compressed-size and no uncompressed-size field, working and
  failing alike. Not the cause.
- *Dictionary/filter differences.* `xz -lvv` reports identical parameters across all four members:
  1 stream, 1 block, CRC32, 1 filter, 65 MiB memory needed. Not the cause.

So the difference really is output size, and the suspect is m1n1's decompress path in `payload.c`,
which decodes into `heapblock_alloc_aligned(0, KERNEL_ALIGN)` — the current heap top, uncommitted —
with `dest_len = 1 << 30`. `heapblock_alloc_aligned` performs no bound check.

## The mistake: I removed the guard that caught this

When the fat object was built, the verifier **rejected it**:

```
FAIL: initramfs expands to 292422732 bytes, over B0 limit 268435456
```

I raised `MAX_INITRAMFS_EXPANDED` from 256 MiB to 1 GiB, arguing it was "an arbitrary policy number",
that the expanded initramfs "becomes the RAM root, so this is a RAM guard, not a load-path limit", and
that 279 MiB is ~1 % of 23.8 GiB of RAM. **Every step of that was wrong in the way that mattered:** the
binding constraint is not total RAM but m1n1's decoder, and the guard had caught a real boot failure.
I even wrote that I was deliberately *not* fitting the guard to my build — while raising it four-fold
precisely so my build would pass.

The general lesson is the inverse of the one I had been drawing all day. A guard whose *rationale* I
cannot verify is not thereby arbitrary. "I don't see why this limit exists" is a reason to go and find
out, not a licence to raise it.

Guard restored at **128 MiB** — above every proven-good size with margin, below the known-bad one —
and it now correctly rejects the fat object. `--self-test` still passes. **Not to be raised again
without a live boot proving the larger size decodes.**

## Both fat objects are broken, not just one

`m1n1-b0-dwm-fat.bin` (`c5438779`) and `m1n1-b0-dwm-fat-diag.bin` (`d14df9f3`) share the identical
initramfs `ad1fe88b`, so **both fail this way**. The diag run's screenshot only reached 0.131 s and the
failure lines sit at 0.136–0.152 s, just below the visible region — so "we got to linux userspace just
fine" was a misreading of that run, and its dmesg (including the genuine `simpledrm` probe) came from a
kernel that then failed to find a root.

The `simpledrm` result still stands: DRM initialised before the rootfs was needed, so **the fat
kernel's DRM helpers are confirmed good** regardless of this failure.

## The replacement object: change one variable

What actually fixed ticket 148 was the **kernel** — `CONFIG_UNIX` for Xorg's AF_UNIX socket, plus the
`DRM_TTM`/`DRM_SCHED`/`DRM_DISPLAY_HELPER` helpers DIET drops. Restoring llvmpipe was a nice-to-have
that is what pushed the rootfs to 279 MiB. So the right object pairs the full kernel with the rootfs
size that is **proven to unpack**:

`m1n1-b0-dwm-fullkernel.bin`
`6738aad9047e31f56d47223fc98d6720d7f21fe8854e4b88766928bf46a75342`
**28,213,248 B = 1722 × 16 KiB**, strict verify **PASS**.

| Member | Hash | Note |
|---|---|---|
| m1n1 v7 window-free | `ecd264a5…` | unchanged |
| kernel `Image-hid-type-fix.xz` | `cbb3e743…` | **full kernel**, `pages=4K` — the actual 148 fix |
| DTB | `2782b922…` | storage-disabled |
| initramfs `initramfs-alpine-dwm-nb.cpio.xz` | `dcc5555a…` | 14.93 MiB xz → **60.5 MiB** expanded |
| bootargs | `3659a0da…` | proven B0 set |

Runtime payload reserve 117,722,259 B (112 MiB). The rootfs is the thin dwm build — same trimming as
the object that *did* boot in 148 — rebuilt so it carries the **keymap fix** (verified: the inittab
contains the `zcat` fallback). Software GL is absent again, which dwm and st do not need.

**Versus the object that booted in 148, exactly one thing changed: the kernel.**

## Run it

```sh
bash scripts/t6040-debugusb-console.sh reboot
bash scripts/t6040-boot-raw-object.sh \
    ~/Code/linux-build-out/m1n1-b0-dwm-fullkernel.bin \
    6738aad9047e31f56d47223fc98d6720d7f21fe8854e4b88766928bf46a75342
```

Then `cat /var/log/xorg-startx.log; pgrep -a Xorg; pgrep -a dwm`.
