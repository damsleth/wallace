# T6040 enrolled appended-payload — RETRACTED root cause + corrected hypothesis

> **RETRACTION 2026-07-25.** This document originally claimed the root cause was
> "m1n1's payload scan looks at its own image". **That conclusion is wrong and is
> withdrawn.** The `[AFK]` bytes found at `base+0x10C000` were **stale RAM from a
> previous boot**, observed with a *payload-free* loader — a mundane explanation I
> failed to control for. Corrected analysis is in the section
> "Corrected analysis (2026-07-25)" at the end; the measurements above it are still
> accurate, only the interpretation was wrong. See also ticket 129.

Measured live over the USB-gadget proxy, with the bare 1.1 MiB rollback loader
(`1394c345`) enrolled and running.

## The finding

m1n1's payload scan looks at memory that contains **m1n1's own image**, not the
appended payload. From the panel log of the *payload-free* loader:

```text
Checking for payloads...
Devicetree compatible value: apple,j614s
Unknown payload at 0x10004938000 (magic: 5b41464b)
No valid payload found
Running proxy...
```

Read of that address over the proxy (`iface.readmem`):

```text
5b 41 46 4b 5d 25 73 20 73 65 6e 64 20 63 6d 64 3a 25 78 ...
ascii: [AFK]%s send cmd:%x arg:%llx state:%d msg:0x%llx.[AFK]%s: Messag
```

Those are **m1n1's own printf format strings** (`src/afk.c` `.rodata`), i.e. magic
`5b41464b` = `"[AFK"`. The scanned address is not an iBoot blob and not our
payload — it is m1n1's own content.

## The arithmetic is right; the memory is not

| Quantity | Value |
|---|---|
| m1n1 runtime base (`u.base`) | `0x1000482C000` |
| m1n1 raw file length (`_payload_start` offset) | `0x10C000` (1,097,728 B, 16 KiB-aligned) |
| scan address (base + file length) | `0x10004938000` — matches the log exactly |
| `bootargs.phys_base` | `0x100032A8000` |
| `bootargs.top_of_kernel_data` | `0x10004FA8000` = base + `0x77C000` (**7.5 MiB**) |
| `bootargs.mem_size` | `0x5CB500000` |

So m1n1 computes the payload address correctly relative to its own base, yet that
memory holds m1n1 image data. iBoot additionally reserves a **7.5 MiB
"kernel data" region starting at m1n1's base** — far larger than the 1.1 MiB
file — and an appended payload lands inside that region.

## Why every payload-carrying enrolled object failed

The scan can never reach the appended bytes, so no enrolled object with an
embedded payload can be discovered, **independent of size, compression, kernel
size, or m1n1 prefix** — matching the observed table exactly (payload objects
loop at 22.2 MB / 15.2 MiB / 9.02 MiB with v1/v2/v3 prefixes; filler objects boot
at 14 MiB and 16 MiB; the identical payload objects boot fine when chainloaded).

The chainload path works because `chainload_image()` explicitly builds the
image+payload at a base it controls, relocates SEPFW, rewrites
`/chosen/memory-map`, and jumps with a known layout. A directly enrolled m1n1
performs none of that.

## Corollaries

- m1n1's fb console **does** render on this panel (the screenshot shows the full
  MMU/AIC/pmgr/display log and `Running proxy...`). So the earlier
  `FB_CONSOLE_ALWAYS` silence on payload objects **is** meaningful: m1n1 either
  never reached `run_actions()` or died before the console was activated in that
  configuration. Either way the payload was never discoverable.
- The `raw` enrollment contract (`--raw --entry-point 2048
  --lowest-virtual-address 0`) is what upstream uses for a **stage-1-only** m1n1.
  Upstream never appends a payload to an enrolled object; it sets `chainload=` and
  loads stage 2 from storage. Appended-payload enrollment is not a supported shape.

## Where to go next

1. **`chainload=` from storage (the upstream shape).** `chainload_load()` ->
   `nvme_init()` + `rust_load_image(spec)`. m1n1's `src/nvme.c` is not SoC-gated
   (generic `/arm-io/ans` + `/arm-io/sart-ans` over RTKit); the SPTM blocker is a
   *Linux*-side ABI problem. **Testable tethered with zero enrollment risk** from
   the proxy shell now attached over USB-C.
2. Investigate whether the raw link layout can host a payload at all (BSS/segment
   placement past `_payload_start`) — i.e. whether the appended-payload shape is
   fixable rather than merely unsupported. Offline source work.
3. USB stage 2 needs Sol's R3 ATC/HPM link *and* mass-storage/FAT in m1n1 (absent;
   U-Boot has it, ticket 025/B1).

## Reusable, already live-proven artifacts

Diet kernel `Image-b0-diet` (16.8 MiB, -67%), `initramfs-alpine-b0-nb2.cpio.xz`
(Norwegian `no-mac` keymap, verified `loaded no-mac.bmap`), m1n1 v2 `5e9dcfd3`
(unconditional early-proxy window, verified), v3 `c59d5820` (+FB_CONSOLE_ALWAYS).
All are independent of the loader architecture and carry over to whichever route
wins.

## Corrected analysis (2026-07-25)

### What is actually proven

1. **The linker layout is self-consistent.** From the exact `1394c345` rebuild:
   `_base=0`, `.rodata@0x50000` (size `0x11E58`), `.stack` ends at `0x10C000`, and
   `_end = _payload_start = 0x10C000` — exactly the 1,097,728-byte file size. So an
   appended payload lands at `base+0x10C000`, which is precisely where m1n1 looks.
2. **m1n1 does not self-relocate.** `src/start.S` only processes PIE relocations
   (`adrp x0, _base`); there is no self-copy, and `_payload_start` resolves
   PC-relative to the running image.
3. **Discovery of appended data WORKS.** The 14 MiB `0xA5` filler object made m1n1
   print `Unknown payload at 0x10005f18000 (magic: a5a5a5a5)` — `a5a5a5a5` is our
   filler, read at the correct address. iBoot loaded it and m1n1 parsed it.
4. **There is no adjacent SEPFW to corrupt.** Every `/chosen/memory-map` entry on
   this machine reads `0xffffffffffffffff`, so the SEPFW-overlap theory is also dead.
5. `bootargs.top_of_kernel_data` = **`base + 0x77C000` (7.5 MiB)**, identical across
   two boots with different bases (`0x1000482C000` and `0x100054E4000`).

### The corrected hypothesis

Point 3 only proves iBoot loaded the object up to `base+0x10C000` — **1.05 MiB in**,
the very start of the filler. It does *not* prove all 14 MiB were loaded. That
reframes everything:

| Enrolled object | Needs data past ~7.5 MiB? | Result |
|---|---|---|
| 14 MiB / 16 MiB filler | **no** (nothing is needed past 1.05 MiB) | boots |
| 22.2 MB gz | yes — kernel member is 16.5 MiB | loop |
| 15.2 MiB xz | yes — kernel member is 11.4 MiB | loop |
| 9.02 MiB diet | yes — initramfs ends at 9.02 MiB | loop |

**Every failing object has payload members extending past ~7.5 MiB; neither
working object needs anything past 1 MiB.** So the candidate cause is that iBoot
loads only a bounded region of the boot object (plausibly the `0x77C000` window
implied by `top_of_kernel_data`), leaving later members **truncated** — a truncated
XZ/gzip member then fails or crashes during decompression, which matches a hard
reset with no exception trace.

Note `top_of_kernel_data` was measured only for the 1.05 MiB bare loader, so
`0x77C000` may be "m1n1 + other boot data" rather than a fixed cap. That is exactly
what the next measurement settles — it is a hypothesis, not a conclusion.

### The measurement that settles it

`linux-build-out/probe-graded-20M.bin`
(`3bf31cde0a22460a40e02d7c523a25ba958b1ae125b0ff59bf0611c33c98725b`, 21,020,672 B):
the exact `1394c345` prefix followed by self-describing 64 KiB blocks from
`0x10C000` to 20 MiB, each starting `b"WLOFS"` + its own offset as u64 LE (304
blocks, all verified). Being payload-free, it boots to `Running proxy` like any
filler probe.

With it enrolled, `scripts/t6040-probe-load-extent.py` (read-only, over the proxy)
reads `base+offset` for each block and classifies it LOADED / zero / stale, printing
the highest loaded offset. That directly measures how much of an enrolled object
iBoot places in RAM.

### Why this matters

If the limit is real and near 7.5 MiB, then **an object that fits entirely inside it
should boot** — and the diet kernel already gets us close: 4.68 MiB (kernel XZ) +
0.05 (DTB) + 1.05 (m1n1) = 5.78 MiB, leaving ~1.7 MiB for a userland. A BusyBox
initramfs (~0.7 MiB) instead of Alpine/OpenRC would fit, which would make an
untethered enrolled B0 boot possible with no USB and no NVMe dependency.

### Process note

This is the third over-conclusion in one session, all the same failure mode:
treating an absence or an ambiguous reading as proof (missing console output;
missing USB gadget node; stale RAM read as a scan-address bug). The measurements
that actually settled things were positive, self-identifying readings — hence a
probe whose every block states its own offset.

## Load-extent measurement (2026-07-25) — hypothesis #3 also dead

Graded probe `probe-graded-20M.bin` (`3bf31cde`, 20.05 MiB, 304 self-describing
64 KiB blocks) enrolled and cold-booted, read back over the proxy with
`scripts/t6040-probe-load-extent.py`:

```text
m1n1 base = 0x100057d0000   top_of_kernel_data = 0x1000724c000 (base+0x1a7c000)
Unknown payload at 0x100058dc000 (magic: 574c4f46)      <- "WLOF", our stamp
HIGHEST LOADED OFFSET SEEN: 0x13cc000 (19.80 MiB)
```

- **iBoot loads the ENTIRE object** — every stamped block out to 19.80 MiB is
  present and self-consistent. There is no truncation and no ~7.5 MiB cap.
- **`top_of_kernel_data` scales with the object**: base+`0x77C000` (7.5 MiB) for the
  1.05 MiB loader, base+`0x1a7c000` (26.5 MiB) for the 20.05 MiB probe — a constant
  ~6.45 MiB of other boot data after the object. It was never a limit.

So the truncation hypothesis is disproven. Size, compression, kernel size, m1n1
prefix, payload discovery, SEPFW adjacency and load extent are now ALL excluded.
The only remaining difference is that m1n1 *acts* on a real payload.

## Where the code points next

- `src/heapblock.c`: `heapblock_init()` sets `heap_base = top_of_kernel_data`.
- `src/payload.c`: `decompress_gz`/`decompress_xz` decompress to
  `heapblock_alloc_aligned(0, KERNEL_ALIGN)` — i.e. into the heap area starting at
  `top_of_kernel_data`, which the measurements show is past the object.

That destination looks clear, so this is a lead, not a conclusion.

## Next measurement, not another hypothesis

The v3 object (`ad156a4b`) carries the **unconditional 5-second early-proxy
window**, and a looping boot re-offers that window every cycle. Connecting to the
USB gadget inside the window yields a **live m1n1 holding the payload before the
Linux handoff**, which allows directly:

1. dumping m1n1's log buffer to see the last thing it printed (the exact failure
   point, without depending on the panel);
2. verifying the payload members in RAM against their known hashes (proving
   load integrity end to end, not just at offset 0x10C000);
3. inspecting `top_of_kernel_data`/heap versus the payload extent for this object.

Procedure: enroll `m1n1-b0-diet-fbvisible.bin` (`ad156a4b`), let it loop, and poll
for `/dev/cu.usbmodem*` while attaching a proxy immediately. No panel observation
required, and nothing is written.

## 5-second window was not catchable — v4 raises it to 60 s

With `ad156a4b` (v3, 5 s window) enrolled and looping, `/dev/cu.usbmodem*` never
appeared across ~40 s of polling (many loop cycles). **This is inconclusive**, and
deliberately not read as "m1n1 dies early": macOS may simply be unable to finish
enumerating a CDC device that exists for at most 5 s per cycle. The graded probe's
gadget was catchable only because `Running proxy` holds it up indefinitely.

To make presence/absence unambiguous, two artifacts with a **60-second** window
(same source, only `EARLY_PROXY_TIMEOUT` changed from 5 to 60):

| Artifact | SHA-256 | Purpose |
|---|---|---|
| `m1n1-t6040-window60-v4.bin` | `62394006675197c3a10488e844f3809ed8ae84a8216cfc33ad437208f7ec6cd4` | v4 m1n1: unconditional window (60 s) + FB_CONSOLE_ALWAYS |
| `probe-window60-bare.bin` | same hash (it *is* the bare m1n1) | **control**: payload-free, must show the window and reach proxy |
| `m1n1-b0-diet-window60.bin` | `9f30b42a70790e2d42381e651d9a77411371f68915cefc8ddf30d4f028ea06a0` | 9.02 MiB diet payload object, strict-verified PASS |

Test order matters — the control first, so the window mechanism is proven before it
is used as a probe:

1. Enroll `probe-window60-bare.bin`. Expect `Waiting for proxy connection...` for a
   full minute, a stable `/dev/cu.usbmodem*` during it, then `No valid payload
   found` -> `Running proxy`. This validates that the window arms at cold boot and
   that a 60 s gadget is catchable.
2. Enroll `m1n1-b0-diet-window60.bin` (same m1n1, plus the payload).
   - **Gadget appears** -> attach inside the window and take the three measurements
     (log buffer for the exact failure point; payload members in RAM verified
     against known hashes; heap/`top_of_kernel_data` versus payload extent).
   - **No gadget, given step 1 passed** -> m1n1 with a payload does not reach
     `run_actions()`, which is then a sound conclusion rather than an inference from
     one ambiguous absence.

## The 5-second period is NOT the proxy window (retracting the previous reading)

Maintainer enrolled `9f30b42a` — identical to `ad156a4b` except
`EARLY_PROXY_TIMEOUT` 5 -> **60** — and the loop period stayed **exactly 5 s**, still
5 attempts then the recovery screen.

So the previous turn's conclusion ("m1n1 reaches the window, waits it out, then dies
in payload_run") is **withdrawn**. If the window were the timer, a 60 s build would
loop at ~60 s. It does not, so with a payload enrolled m1n1 apparently never reaches
the wait loop — or does not reach `run_actions()` at all.

**What the 5 s actually is: unknown.** It is identical across two m1n1 builds and is
not any timeout we control. Candidates, none verified: an iBoot-side boot timeout, a
watchdog that `wdt_disable()` does not actually silence on M4 (m1n1 prints "Primary
WDT disabled"/"Secondary WDT disabled", which is a claim, not a confirmation), or a
SEP/SMC-driven reset. Notably a payload-free object at the same base runs
indefinitely at `Running proxy`, so whatever fires at 5 s is triggered by the
payload-carrying case, not by the object merely being large.

## Next: RAM forensics instead of another inference

RAM survives a warm reset — proven earlier in this very investigation, when stale
`[AFK]` bytes from a previous boot were misread as a live scan result. That property
is now usable as a tool.

m1n1 allocates its stage-2 log buffer at the **top of RAM**
(`src/kboot.c:2751`, `top_of_memory_alloc(LOGBUF_SIZE + LOGBUF_TOP_GUARD_SIZE)`) during
`kboot` and registers it as a console iodev, so a boot that reached kboot leaves its
tail output in RAM for the *next* boot to read.

`scripts/t6040-ram-forensics.py` (read-only) scans the top MiBs of RAM for markers
(`Uncompressing`, `XZ decode`, `uncompressed to`, `Preparing to boot`, `Vectoring to
next stage`, `Linux version`, `Kernel panic`, `Unhandled exception`, ...) and prints
the longest printable runs around any hit.

Procedure: with the failing object having just looped, enroll **any payload-free
object** (`probe-window60-bare.bin` or `rollback-m1n1-1394c345.bin`), boot to
`Running proxy`, and run the script. Binary outcome:

- **markers found** -> the failing boot reached kboot/Linux, and the recovered text
  states how far it got;
- **nothing found** -> it died before kboot, i.e. during payload decompression or
  earlier, which also narrows the 5 s trigger.

Either way this is a reading, not an inference.

## RAM forensics: the failing boot never reached kboot

First attempt was invalid — the read aborted at the top chunk
(`Device not configured`) and the script still printed "no markers"; the failure also
crashed m1n1 (base changed `0x10005d14000` -> `0x10004618000`, i.e. it rebooted).
Two mistakes: `top_of_memory_alloc` *decrements* `mem_size`, so `phys_base+mem_size`
is the already-reduced top; and the scan must stop at the first read error rather
than continue past it.

Redone walking upward in 16 KiB reads with a hard stop:

```text
top(current mem_size) = 0x105ce7a8000 ; m1n1 base = 0x10004618000
readable ceiling = 0x105ce7a4000 (first failing read)
markers: NONE
printable runs found: 0
```

The scan **completed** (ceiling found one page below top, no mid-region abort) and
the top 2 MiB contains no log text at all. m1n1 creates that logbuf only during
`kboot`, so **the failing boot never reached kboot**.

## The discriminator I had been overlooking: magic bytes in the appended region

Reviewing what separates working from failing objects — including a line I printed
myself when building the probes, `no gz/xz/fdt magic in tail: True`:

| Object | Appended region contains gz/xz/FDT magic? | Result |
|---|---|---|
| `probe-m1n1-16M` (zeros) | no | boots |
| `probe-nz-14M` (`0xA5`) | no | boots |
| `probe-graded-20M` (`WLOFS` stamps) | no | boots |
| 22.2 MB gz object | **yes** (gzip + FDT) | 5 s loop |
| 15.2 MiB xz object | **yes** (xz + FDT) | 5 s loop |
| 9.02 MiB diet objects (v2/v3/v4) | **yes** (xz + FDT) | 5 s loop |

**Every booting object lacks those magics; every failing object has them.** This
correlation is perfect across six objects and was never tested, because all my
filler probes were deliberately built magic-free.

Two readings, and they are very different:
1. **m1n1-side**: m1n1 recognises the payload and dies acting on it — but the RAM
   forensics say kboot was never reached, and the loop period is independent of
   `EARLY_PROXY_TIMEOUT`, which fits m1n1 not getting that far.
2. **iBoot-side**: iBoot itself inspects the object and refuses/faults on content it
   recognises (an embedded FDT, a compressed member), never entering m1n1 — which
   fits the total absence of m1n1 console output, gadget, and logbuf, and a fixed
   ~5 s retry cadence with a 5-attempt limit.

## Two cheap discriminating probes

| Artifact | SHA-256 | Content | Expected if m1n1 runs |
|---|---|---|---|
| `probe-fdt-only.bin` | `b235abae31d42795e2891d9cf2792bbfd2d7568ffda5721fa4067fe4a03624ab` | m1n1 + **DTB only** (1.10 MiB) | devicetree reported, no kernel -> `No valid payload found` -> `Running proxy` |
| `probe-kernel-dtb.bin` | `18e4332068f7bfe356ef5263ed4acec4c1dc571645f1279d9dcac8091824fce6` | m1n1 + bootargs + xz kernel + DTB (5.78 MiB) | smallest real autoboot payload (kernel+DTB suffices) |

- `probe-fdt-only.bin` **loops** -> the mere presence of an FDT in an enrolled object
  is fatal, which points squarely at iBoot-side content inspection and makes the
  appended-payload shape unusable regardless of m1n1.
- `probe-fdt-only.bin` **boots** but `probe-kernel-dtb.bin` **loops** -> content
  presence is fine and the failure is in m1n1's decompress/kboot path, with the
  initramfs excluded as a factor.
- Both boot -> the initramfs member specifically is implicated, and the object is
  only ~1.7 MiB from a configuration that works.

## probe-fdt-only LOOPS — size is irrevocably excluded, content is confirmed causal

`probe-fdt-only.bin` (`b235abae`, **1.10 MiB** = m1n1 + one DTB + terminator) loops
exactly like the multi-megabyte payload objects, while payload-free fillers of 14, 16
and 20 MiB all boot. A 1.1 MiB object failing where a 20 MiB object succeeds ends any
size-based explanation permanently, and confirms the trigger is the **content** of the
appended region.

Note the expected behaviour had m1n1 run: a DTB with no kernel does not satisfy
autoboot, so m1n1 should print `Found a devicetree…`, then `No valid payload found`,
activate the fb console and reach `Running proxy`. It does not.

## Isolating iBoot-side rejection from m1n1-side fault

The free observation is the panel: with the plain `1394c345` prefix the fb console is
activated on the no-payload path, so if m1n1 executed at all its log would be visible.
Only the Apple logo -> m1n1 never runs -> iBoot refuses the object by content. Text on
the panel -> m1n1 runs and faults while handling the DTB payload.

Four matched probes, ~1.11 MiB each, differing **only in the first 4-6 bytes after the
m1n1 image** — so size, terminator and layout cannot account for any difference:

| Artifact | SHA-256 | Tail begins with |
|---|---|---|
| `probe-magic-fdt-invalid.bin` | `20d30cf52b769e80822ad1cdbc62fa4f329cd9e1c0b06be6299119b2ffaf6844` | `d0 0d fe ed` then `0xA5` filler (magic present, **not** a valid tree) |
| `probe-magic-gz.bin` | `85c40daefcdea4df6f82309ab393a970fbcb7e508685df4202686c06d3308e72` | `1f 8b` then filler |
| `probe-magic-xz.bin` | `9416fa103c7520ce06082eb09f8fca0dcf84ac7f97ed542aea118a69c8ebd921` | `fd 37 7a 58 5a 00` then filler |
| `probe-magic-none.bin` | `cbf751e5abdfb6ef07f533ad15c388e6f16a98da9a96cce30108faaf31c51ddd` | `a5 a5 a5 a5` then filler (**control**) |

Readings:

- control boots and any magic probe loops -> **a recognised magic alone is fatal**,
  which can only be iBoot-side content inspection (m1n1 would merely reject a bogus
  tree/stream and continue to the proxy). Appended-payload enrollment is then dead for
  good, and the U-Boot/USB stage-2 route (ticket 128) is the way forward.
- all four boot while the valid-DTB probe loops -> it is not the magic but a *valid*
  structure, i.e. m1n1 faults while processing a real payload record — an m1n1 bug,
  and fixable.
- control loops too -> something about a terminator/short-tail object rather than
  content, and the whole framing needs revisiting.

Run the control first so the instrument is validated before it is used.

## CONCLUSION: iBoot never enters m1n1 when the appended region looks like a payload

`probe-fdt-only.bin` (1.10 MiB, m1n1 + one DTB) shows **only the Apple logo**, then the
5 s loop. That is decisive, because the probe was built so that a running m1n1 *must*
be visible: a DTB with no kernel does not satisfy autoboot, so m1n1 would print
`Found a devicetree…` and `No valid payload found`, and the no-payload path calls
`fb_set_active(true)`, which renders its whole log on the panel (exactly as captured in
the maintainer's screenshot of the bare loader).

Five independent lines now agree that **m1n1 does not execute** for payload-carrying
enrolled objects:

1. no m1n1 text on the panel, while the identical prefix renders a full log when the
   appended region is magic-free;
2. no USB gadget, even with a 60 s unconditional early-proxy window;
3. no kboot logbuf anywhere in the top 2 MiB of RAM;
4. loop period is exactly 5 s for both `EARLY_PROXY_TIMEOUT=5` and `=60`, so no m1n1
   timeout is involved;
5. a 1.10 MiB object fails while payload-free objects of 14/16/20 MiB boot, so it is
   content, not size.

So the failure is **iBoot-side**: it inspects the enrolled object and declines to run
it, retrying ~5 times before the "needs to be reinstalled" screen. The precise check
inside iBoot is not visible to us and is deliberately left unstated here.

**Consequence:** the appended-payload enrollment shape is unusable on J614s as-is.
Everything downstream of it (m1n1, kernel, DTB, initramfs, decompression) was never
reached and is not implicated — all of those components remain proven via chainload.

## Promising revival path: payload obfuscation

If iBoot declines the object because the appended bytes are *recognisable*, then
storing them **masked** removes the trigger while changing nothing about the boot:

- build the object with every appended byte XOR-masked (single-byte key, or a keystream)
  so no gz/xz/FDT/cpio magic and no ASCII `chosen.bootargs=` appears anywhere;
- add a small m1n1 patch that un-masks the payload region in place at the very start of
  `run_actions()`, before `payload_run()` — the length and key are compile-time
  constants, so this is a short, reviewable loop with no allocation;
- everything after that is the already-proven path.

This works under either reading of the iBoot check — a magic-byte scan finds nothing,
and a structural validator finds nothing parseable. It needs no USB, no NVMe, no HPM
work, and reuses the artifacts already verified today (diet kernel, Norwegian OpenRC
initramfs, m1n1 v2/v3/v4 variants).

Worth doing first, cheaply: run `probe-magic-none.bin` (control) and one magic probe to
learn whether a bare magic byte is enough to trigger the refusal. That is not required
for the obfuscation build, but it tells us how careful the masking has to be, and it
documents the actual trigger for any future upstream conversation.
