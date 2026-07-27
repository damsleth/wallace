# Ticket 160: the initramfs decode limit is content-dependent, and now checkable offline

## The harness (the durable deliverable)

`scripts/t6040-minilzlib-harness.sh` builds a host binary around m1n1's **own** `src/minilzlib`
(sources copied at build time, never vendored) plus a one-line stub `utils.h` — the decoder is
byte-identical to what runs on the machine. `scripts/t6040-minilzlib-harness.c` mirrors
`payload.c:decompress_xz` exactly: `dest_len` starts at `1 << 30`, then `XzDecode()` into a real buffer.

**It reproduces the machine's pass/fail exactly**, verified against every object we have:

| object | expanded | harness | machine |
|---|---|---|---|
| `initramfs-alpine-b0-nb2` | 13 MiB | decodes | boots |
| `initramfs-alpine-dwm-udev` | 62 MiB | decodes | boots (dwm) |
| `initramfs-alpine-dwm-hidpi` | 62 MiB | decodes | boots (dwm) |
| `Image-hid-type-fix` | 50 MiB | decodes | boots |
| `initramfs-alpine-dwm-fat` | 278 MiB | **XZ decode failed** | **fails: no initrd, rdinit -2** |

Because it reproduces on the host with a real 1 GiB buffer, **the failure is intrinsic to `XzDecode`,
not target memory** — so any candidate initramfs can be cleared (or condemned) with **zero rig time**:

```sh
bash scripts/t6040-minilzlib-harness.sh build
/private/tmp/t6040-lzharness/lzharness <initramfs.cpio.xz>   # rc 0 = will decode on the machine
```

## The limit is NOT a simple size — it is content/level dependent

The earlier "(97.3, 278.9] MiB" framing assumed a pure size threshold. That is **wrong**:

- **200 MiB of zeros: decodes.** (compresses to 30 KB)
- **200 MiB of real cpio at `xz -6`: decodes.** (compresses to ~49 MiB)
- **192 MiB of real cpio at `xz -9e`: decodes.** (compresses to ~46 MiB)
- **278 MiB of real cpio at `xz -9e`: fails.** (compresses to ~67 MiB)

So the same uncompressed size passes or fails depending on **compression level and content**, which
points at compressed structure — LZMA2 chunk count / range-decoder state at `-9e`'s 64 MiB dictionary —
not the uncompressed byte count. The exact mechanism (a `false` return deep in `Lz2DecodeStream` or the
`XzDecodeIndex` VLI meta-check) is a genuine follow-up; filed as **ticket 171**.

(An offline `-9e` bisect over 160/192/224/240/256/272/278 MiB was still refining the crossover when this
was written; 160 and 192 MiB confirmed passing. The crossover is somewhere in (192, 278] MiB for `-9e`
real content, but it is **not** a portable constant — see below.)

## Consequence for the verifier guard

Because the true invariant is content-dependent, **no single expanded-size number is exactly right**.
The right design is two-layer:

1. **The harness is the authoritative pre-enroll check.** Run the actual `.cpio.xz` through `lzharness`;
   it answers the real question (does *this* object decode) with no rig time and no guessing.
2. **The verifier's `MAX_INITRAMFS_EXPANDED = 128 MiB` stays as a cheap backstop**, not a truth. Every
   object that has ever booted is ≤ 62 MiB expanded, and everything tested up to 192 MiB `-9e` decodes,
   so 128 MiB rejects nothing real while still catching a runaway. It must not be raised toward the
   observed crossover, because the crossover moves with content and compression settings.

`t6040-raw-object-verify.py` should gain an optional `--harness` mode that shells out to `lzharness` for
the definitive check; noted on ticket 160 as the finishing step.
