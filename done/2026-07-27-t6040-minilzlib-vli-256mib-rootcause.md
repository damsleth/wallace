# Ticket 171 (closes) + 160 correction: the decode limit is exactly 256 MiB, a VLI truncation bug

## Root cause — one line

`src/minilzlib/xzstream.h`:

```c
typedef uint32_t vli_type;
#define VLI_BYTES_MAX (sizeof(vli_type) * 8 / 7)   /* = 32 / 7 = 4 (integer truncation) */
```

A full 32-bit value needs `ceil(32/7) = 5` base-128 bytes, but this gives **4**, capping VLIs at
28 bits = `2^28 - 1`. The XZ **index** encodes `UncompressedBlockSize` as a VLI, so `XzDecodeVli()`
rejects any block whose uncompressed size needs the 5th byte — i.e. **>= 2^28 = 256 MiB** — at
`xzstream.c:117` (`bitPos == 7 * VLI_BYTES_MAX`). `XzDecode` then returns false, m1n1 prints
`XZ decode failed`, passes no initrd, and the kernel dies with `rdinit=/sbin/init failed: -2`.

## How it was found (all offline, the ticket-160 harness)

Instrumented the harness's copy of the decoder (`return false` → an expression that logs
`__FILE__:__LINE__`). The 278 MiB fat image failed first at **`xzstream.c:117`**; the 240 MiB image
had no failure. That line is inside `XzDecodeVli`, called from `XzDecodeIndex` to read
`UncompressedBlockSize`.

## The limit is exactly 2^28, and NOT content-dependent

Boundary confirmed on the harness:

| uncompressed | vs 2^28 (268435456) | result |
|---|---|---|
| 240 MiB (251658240) | under | decodes |
| 255 MiB (267386880) | under | decodes |
| 256 MiB (268435456) | == 2^28 | **fails** |
| 278 MiB (291504128) | over | **fails** |

**Correction to `done/2026-07-27-t6040-minilzlib-decode-limit-harness.md`:** I earlier called the
limit "content/level dependent" because 200 MiB of zeros and 200 MiB at `xz -6` decoded while 278 MiB
at `-9e` failed. That was premature — all three passing cases are simply **< 256 MiB**, and the one
failing case is **> 256 MiB**. Content and compression level are irrelevant; the cap is a clean
uncompressed-size limit at exactly 2^28. The earlier "ruled out size threshold" reasoning was wrong.

## The fix — proven

`patches/m1n1-minilzlib-vli-bytes-max.patch` (applies cleanly to m1n1):

```c
#define VLI_BYTES_MAX ((sizeof(vli_type) * 8 + 6) / 7)   /* ceil: 5 bytes, full uint32 range */
```

With it, the harness decodes the 278 MiB fat image (`292422732 bytes`) and all normal images are
unchanged. **Not yet applied to the m1n1 tree** — m1n1 is a separate repo with its own commit series,
so it awaits the maintainer's go-ahead (same policy as the shell.py fix). It is a genuine upstream bug
in the vendored minilzlib and worth reporting upstream.

## Practical consequence for Wallace

Mostly academic: every real image is <= 62 MiB expanded, and the verifier guard is 128 MiB. But the
picture is now exact rather than fuzzy:

- The verifier's `MAX_INITRAMFS_EXPANDED = 128 MiB` is comfortably below the true **256 MiB** hard cap
  and can stay as-is.
- If a >256 MiB RAM root is ever wanted, applying the one-line m1n1 patch raises the cap to 4 GiB (the
  next real limit being RAM and the `1 << 30` output buffer in `decompress_xz`).
- The `t6040-minilzlib-harness.sh` remains the authoritative pre-enroll check; it now has a precisely
  understood failure mode.
