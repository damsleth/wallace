# T6040 enrolled-object payload limit — the zeros-probe was invalid (2026-07-25)

Both payload-carrying B0 objects boot-loop when **enrolled**, while the same
objects boot fine when **chainloaded**. Root-cause evidence and a corrected
experiment.

## Data

| Enrolled object | Tail content | Result |
|---|---|---|
| `46237ade` 22.2 MB (gz payload) | real payload | **loop** |
| `4340ec37` 15.2 MiB (xz payload) | real payload | **loop** |
| `probe-m1n1-16M` 16 MiB | **zeros** | boots to `Running proxy` |

## Decisive measurement: m1n1 never executes

Read-only KIS attach *while the enrolled `4340ec37` was looping*
(`t6040-debugusb-console.sh`, no reboot, no payload sent):

- `kisd`: `Guessed base = 0x548700000` → `Device opened` → after ~33 s
  `Disconnected: I/O Error 0xe00002ed` (the reset), then `Waiting for device`.
- **`/tmp/m1n1-console.log` = 0 bytes** across the whole loop window. A normal
  m1n1 boot emits ~15 KB per boot.

So the failure is **before m1n1's first instruction** — iBoot does not reach the
raw entry point. Nothing in m1n1, the payload parser, minilzlib, the kernel, or
Linux is implicated (and the chainload path proved all of those work with this
exact object).

## Why the 16 MiB probe was a false negative

The padded probes were `m1n1.bin` + **zero** fill. m1n1 only needs its first
~1 MiB to reach `Running proxy`, and it never reads the zeros — so a padded
probe cannot exercise payload loading at all. Worse, if iBoot's load region is
followed by structures iBoot still needs (its own data, SEPFW staging, the ADT
under construction), then:

- a **zero** tail overwrites that area harmlessly → iBoot survives → m1n1 runs;
- a **real-data** tail corrupts it → reset before entry.

That single mechanism explains all three rows above, and means the effective
limit is **below 15.2 MiB** — the zeros ladder was structurally incapable of
finding it. Claiming "budget >= 16 MiB" from it was wrong.

## Corrected probe: non-zero filler

`linux-build-out/probe-nz-{2,4,6,8,10,12,14}M.bin` — exact `1394c345` prefix
(verified byte-identical) + `0xA5` filler to the target size, containing **no**
gz/xz/FDT magic, so m1n1 (if it runs) finds no valid payload and falls through
to the proxy. Therefore:

- **boots to `Running proxy`** → an object of that size with live tail data is
  safe for iBoot;
- **loops silently** → that size exceeds the real limit.

Bisect (suggest 8 MiB first, then halve/double) to bracket the wall. The largest
passing size is the true object budget.

## Consequence for B0

The payload is ~14.8 MiB compressed (kernel 10.9 MiB XZ + initramfs 3.2 MiB +
DTB), so if the wall lands materially below ~15 MiB, an embedded RAM-root object
cannot fit and B0 needs one of:

1. **Kernel diet** — the Image is 50.8 MiB raw / 10.9 MiB XZ; a
   T6040-essentials-only config should cut it hard. Highest-value next build.
2. **Smaller userland** — BusyBox-only initramfs instead of Alpine/OpenRC
   (already proven bootable earlier in bring-up) saves ~3 MiB.
3. **Stage-2 from storage** — `chainload=`/`chainload_load()` in m1n1 reads via
   **`nvme_init()`**, i.e. internal NVMe, which stays SPTM-blocked; a USB/FAT
   stage-2 loader does not exist in m1n1 (U-Boot has it, ticket 025/B1, and
   needs the R3 host link first). Not a near-term option.

## Rig state

Released `--state wedged`: the M4 still has a payload-carrying object enrolled,
so it loops and the next acquirer cannot get a proxy until the maintainer
re-enrolls a proxy m1n1 from 1TR (`rollback-m1n1-1394c345.bin`, or any padded
probe). Enrollment is 1TR-only on this machine (memory `kmutil-enroll-1tr-only`).
