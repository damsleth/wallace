# T6040 enrolled appended-payload ROOT CAUSE (2026-07-25)

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
