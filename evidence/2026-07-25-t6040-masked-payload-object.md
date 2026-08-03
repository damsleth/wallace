# T6040 B0 masked-payload object (ticket 133) — built (2026-07-25)

Response to ticket 129's conclusion: iBoot declines to execute an enrolled raw object
whose appended region looks like a payload (`probe-fdt-only.bin`, 1.10 MiB = m1n1 +
one DTB, never enters m1n1 and loops every 5 s, while payload-free objects of 14/16/20
MiB boot). If the refusal keys on *recognisable* content, storing the payload masked
removes the trigger while changing nothing about the boot itself.

## Artifact

```text
m1n1-b0-masked.bin
SHA-256 ef8e0a30bdb8505616aa823af99cc1fa0c22cc64d0b796c90cce76c3423ce8d9
size 9,455,156 B (9.02 MiB), entry 0x800
  = m1n1 v5 (c69d221148c5e6515d0a6b9e450123f4e757a860a3f7e337b83c5c3f00b85fa2)
  + XOR-0x80-masked payload (8,357,428 B)
```

Reproducible: two full runs of `scripts/t6040-build-masked-object.sh` produced the
identical object hash.

## The mask

Key **0x80**, single byte, applied to the whole appended region. Verified on the
built object:

| Check | Result |
|---|---|
| xz magic (`fd 37 7a 58 5a 00`) in masked region | absent |
| FDT magic (`d0 0d fe ed`) | absent |
| cpio magic (`070701`) | absent |
| ASCII `chosen.` | absent |
| first 16 masked bytes | `e3e8eff3e5eeaee2efeff4e1f2e7f3bd` — all >= 0x80, i.e. `chosen.bootargs=` rendered non-printable |
| un-mask reproduces plaintext | yes, byte-exact |
| unmasked payload == payload of the strict-verified `9f30b42a` object | yes |

Two things learned while choosing the key, both worth recording:

- **A 2-byte gzip magic (`1f 8b`) cannot be avoided** in ~8 MB of high-entropy data
  for *any* single-byte key (149 incidental occurrences at key 0x80). By the same
  argument it cannot be what iBoot keys on, since every real kernelcache contains it
  incidentally. It is reported, not required absent.
- **A low printable-ASCII *ratio* is unachievable and was the wrong criterion** —
  compressed data is ~37% printable by nature (95 of 256 byte values). The right test
  is that no legible *string* survives, which a key >= 0x80 guarantees (every ASCII
  byte maps to >= 0x80), reinforced by rejecting any printable run >= 24 chars.

## The m1n1 side

`patches/m1n1-payload-unmask.patch` (30 lines) on `a61fd099`, built with
`-DPAYLOAD_MASK_KEY=128 -DPAYLOAD_MASK_LEN=8357428UL -DFB_CONSOLE_ALWAYS=1`:

```c
#ifdef PAYLOAD_MASK_KEY
    {
        u8 *pm = (u8 *)_payload_start;
        for (size_t i = 0; i < (size_t)PAYLOAD_MASK_LEN; i++)
            pm[i] ^= (u8)PAYLOAD_MASK_KEY;
        printf("payload: un-masked %lu bytes at %p (key 0x%02x)\n", ...);
    }
#endif
```

placed at the start of `run_actions()`, before `payload_run()`. Key and length are
compile-time constants, so the object and the m1n1 that reads it are matched by
construction; a mismatched pair simply fails to parse rather than doing anything
unsafe. `FB_CONSOLE_ALWAYS` is included deliberately — see below.

## Why this test is self-diagnosing

Because the fb console is forced on before the payload is touched, the panel
distinguishes the two possible failures without any cable:

- **panel shows m1n1's log, including `payload: un-masked 8357428 bytes …`** -> iBoot
  ACCEPTED the object and m1n1 ran. Anything after that is an m1n1/boot problem we can
  read directly, and the ticket-129 iBoot-refusal theory is confirmed by the contrast.
- **panel shows only the Apple logo, 5 s loop** -> iBoot still refused. The check is
  therefore not keyed on recognisable magic/structure, which falsifies the obfuscation
  premise and redirects effort to ticket 128 (U-Boot/USB stage 2).
- **panel shows the un-mask line then a failure** -> the mask works and the remaining
  bug is downstream, with everything up to `payload_run()` proven.

## Status

Built, verified, reproducible, **not yet booted**. A tethered chainload smoke is the
lower-risk first step but needs a working loader enrolled first (the rig currently has
the looping `probe-fdt-only` enrolled); enrolling `m1n1-b0-masked.bin` directly is
equally well-instrumented thanks to the forced fb console, and is the test that
actually answers the question. Enrollment is 1TR-only and maintainer-executed.
