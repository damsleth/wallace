# Ticket 156: graded-probe builder + 512 MiB / 1 GiB probes (offline half done)

## The builder

`scripts/t6040-build-graded-probe.py` — new. Builds a self-describing probe object:
a payload-free m1n1 loader, then `0x5a` filler carrying `b"WLOFS" + u64le(offset)` at every
`0x10C000 + k*0x10000`, so a single memory read at any 64 KiB step says whether that offset
was loaded. Read back with the existing `scripts/t6040-probe-load-extent.py`, which already
honours `PROBE_LIMIT_MIB` and needed no change.

The layout was **reverse-engineered from the live-proven `probe-graded-256M.bin`** rather than
invented: 4080 stamps, filler `0x5a`, final block truncated to EOF.

### Validated by byte-exact reproduction

The builder regenerates the enrolled-and-proven 256 MiB probe **byte-for-byte**:

```
built  c7fcfa71015979391c5c9b85243fe9b04f996877e6b78dd5daa1615edad87cc3
proven c7fcfa71015979391c5c9b85243fe9b04f996877e6b78dd5daa1615edad87cc3   cmp: identical
```

That hash is the one recorded in `evidence/2026-07-25-t6040-object-size-ceiling.md`, so the builder is
provably equivalent to whatever produced the probe that actually booted. It also self-checks every
stamp it wrote and asserts 16 KiB alignment before writing the file.

## The new probes

| Object | Size | sha256 | Stamps |
|---|---|---|---|
| `probe-graded-512M.bin` | 512 MiB = 32768 × 16 KiB | `59eb0a1a14ded4deb26fb3aeb44041a140c0a76ecbec3be74c5830cb24766cdc` | 8176 |
| `probe-graded-1024M.bin` | 1024 MiB = 65536 × 16 KiB | `91e4d692603622dd4bb1fce7f66ef044e0888393dda3639c02266af854725ccb` | 16368 |

Both built on `rollback-m1n1-1394c345.bin` (`1394c345…`) — **the loader currently enrolled**, and the
same base the proven 256 MiB probe used, so the only variable versus that measurement is size.

## What is measured, and what is deliberately not

The probe stamps are **not** a valid payload, on purpose: m1n1 prints
`Unknown payload … (magic: 574c4f46)` → `No valid payload found` and drops to `Running proxy`, which
is the state the read-back needs.

This measures **iBoot's load extent** only. It says nothing about the two constraints that are not
about size — an enrolled object's total size must be a whole multiple of 16 KiB (ticket 129), and
m1n1's xz decoder advertises 1 GiB — and nothing about decompression latency, which for real objects
may bind well before any size limit (single-block xz is single-threaded).

## Rig half (needs the maintainer: `kmutil` is 1TR-only)

Enroll a probe, boot to `Running proxy`, then:

```sh
PROBE_LIMIT_MIB=512 M1N1DEVICE=/dev/cu.usbmodemJ22GYCN4YG1 \
    ~/Code/m1n1/venv/bin/python scripts/t6040-probe-load-extent.py
```

Expected if there is still no ceiling: `HIGHEST LOADED OFFSET SEEN` lands one 64 KiB step short of the
total (the 256 MiB probe reported `0xff0c000` = 255.05 MiB). A ceiling shows up as stamps going
`LOADED` → `zero`/`stale` at a consistent offset.

Do 512 MiB first; only go to 1 GiB if 512 loads fully. Restore the daily-driver object afterwards.

**Correction to the record while here:** 512 MiB was never established — the maintainer's assumption
of it was reasonable but untested. 256 MiB is the largest size *measured* good (ticket 137), and the
verifier's `MAX_OBJECT_SIZE` is still that number.
