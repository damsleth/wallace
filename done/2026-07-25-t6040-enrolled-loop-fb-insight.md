# T6040 enrolled-payload loop — panel silence explained; fb-visible probe (2026-07-25)

The 9.02 MiB diet object `d645bf95` also boot-loops, so **object size is
definitively excluded**: payload-carrying objects loop at 22.2 MB, 15.2 MiB and
9.02 MiB, while filler objects boot at 16 MiB (zeros) and 14 MiB (`0xA5`).
The discriminator is "carries a parseable payload".

## Finding 1 — m1n1's fb console is OFF on the payload path

`src/main.c` `run_actions()`:

```c
    printf("Checking for payloads...\n");
    if (payload_run() == 0) { printf("Valid payload found\n"); return; }
    fb_set_active(true);                 /* only on the NO-payload path */
    printf("No valid payload found\n");
```

`display_init()`/`fb_init()` run before `run_actions()`, but the console is only
*activated* when no payload is found. Consequences:

- **filler probe** -> no payload -> `fb_set_active(true)` -> m1n1 text renders on
  the panel -> looks healthy;
- **payload object** -> payload found -> immediate `return` -> **fb console never
  activated** -> the panel keeps showing the Apple logo while m1n1 runs
  invisibly, then Linux takes the framebuffer (the ~1 s black) and dies -> reset.

So the maintainer's "Apple logo -> black 1 s -> Apple logo" is fully consistent
with **m1n1 executing normally**. Panel silence is not evidence of failure, and
the earlier "m1n1 never runs" claim stays retracted.

## Finding 2 — iBoot places SEPFW immediately after the m1n1 image

`src/payload.c:256` matches an IMG4 blob with the comment **"SEPFW after m1n1"**,
i.e. m1n1 expects iBoot to append SEPFW right after the enrolled image. And
`chainload_image()` (src/chainload.c:37-87) explicitly **copies SEPFW and rewrites
`/chosen/memory-map` SEPFW** before jumping to the next image.

A *directly enrolled* m1n1 never performs that relocation — it is only on the
chainload path. That is a concrete, mechanism-level difference between the working
path (enrolled bare m1n1 -> chainload payload object -> Linux, proven repeatedly)
and the failing path (enrolled payload object -> Linux). Upstream Asahi never
enrolls a payload-carrying object either (stage 1 is small and pulls stage 2 from
NVMe via `chainload_load()`/`nvme_init()`), so this configuration is genuinely
untested upstream.

## Finding 3 — iBoot gives up with "needs to be reinstalled"

After ~1 minute of looping the M4 lands on a recovery screen: *"The version of
macOS on the selected disk needs to be reinstalled"* / *"use recovery to reinstall
macOS or select another startup disk"*. This is iBoot declaring the **m1n1 volume**
unbootable after repeated failures. The main macOS volume is unaffected.

Recovery (do **not** choose Reinstall): *select another startup disk* ->
`Macintosh HD` -> main macOS; then from 1TR re-enroll a known-good object
(`rollback-m1n1-1394c345.bin` or `probe-nz-14M.bin`).

This leans toward iBoot rejecting/failing the object rather than a late Linux
panic, but both models still fit the evidence.

## Next test — the fb-visible object (settles it)

`patches/m1n1-fb-console-always.patch` adds `-DFB_CONSOLE_ALWAYS`, which calls
`fb_set_active(true)` **before** `payload_run()`, so an enrolled payload boot
renders m1n1's console on the internal panel.

```text
m1n1 v3 (fb-visible)        c59d5820df4ef3d98a41e620a48e14a097cc5bf952c43226f3dac693268b8472
object m1n1-b0-diet-fbvisible.bin
                            ad156a4b91fd52e64439c21ccd8c680d8f752869b6cfe73d46f5b54c5f30fb7e
9,455,156 B (9.02 MiB), entry 0x800, strict verify PASS
```
(m1n1 v3 = v2's unconditional early-proxy window + FB_CONSOLE_ALWAYS.)

Discriminator when enrolled and cold-booted:

- **m1n1 text appears on the panel** (banner, `Checking for payloads...`, XZ
  decode lines) -> m1n1 runs; read the exact failure point, and the SEPFW
  hypothesis becomes testable directly.
- **Nothing but the Apple logo** -> iBoot never reaches m1n1's entry with a
  payload-carrying object, i.e. an iBoot-side load/verify rejection.

Either result eliminates half the hypothesis space, on one cold boot, with no
cable required.
