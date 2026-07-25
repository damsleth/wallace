# T6040 embedded-payload enrollment is a dead end (2026-07-25)

## Conclusion

**An enrolled raw boot object that carries an embedded m1n1 payload does not boot
on this machine, at any size.** Maintainer reverted to an m1n1-only enrolled
loader (the proven tethered configuration).

| Enrolled object | Payload | Size | Result |
|---|---|---|---|
| `probe-m1n1-16M` (zeros) | no | 16 MiB | boots to `Running proxy` |
| `probe-nz-14M` (`0xA5`) | no | 14 MiB | boots; m1n1 reports reading the tail |
| `46237ade` gz B0 | **yes** | 22.2 MB | loop |
| `4340ec37` xz B0 | **yes** | 15.2 MiB | loop |
| `d645bf95` diet B0 | **yes** | 9.02 MiB | loop |
| `ad156a4b` diet + FB_CONSOLE_ALWAYS | **yes** | 9.02 MiB | loop |

Size is excluded. Compression format is excluded (gz and xz both fail). Kernel
size is excluded (67% smaller still fails). The m1n1 prefix is excluded (v1/v2/v3
all fail, and the same prefixes boot fine as filler objects). Every payload
component is independently proven: **the identical objects boot correctly when
chainloaded** over KIS into a running m1n1 (tickets 089/100 and the diet/nb2
smokes, including Alpine, OpenRC, `event0`, watchdog, Norwegian keymap).

After ~1 minute of retries iBoot declares the m1n1 volume unbootable
("needs to be reinstalled"); that screen's Reinstall option just enters recovery
with a usable Terminal, so a failed object costs one re-enroll, not a rebuild
(memory `kmutil-enroll-1tr-only`).

## Caveat on the last probe

`FB_CONSOLE_ALWAYS` was meant to discriminate "m1n1 runs and Linux dies" from
"iBoot never reaches m1n1" by forcing the panel console on before
`payload_run()`. It showed nothing — but **m1n1's own fb console was never
confirmed to render on this machine** (the panel output seen previously was
Linux's fbcon under simpledrm, not m1n1). So the probe is **inconclusive**, not
proof of an iBoot-side rejection. To make it conclusive one would first enroll a
*filler* probe and check whether m1n1's own text appears on the panel; that was
not done because the practical conclusion (embedded payloads don't boot) is
already established by the table above.

## Why this configuration was always unusual

Upstream Asahi never enrolls a payload-carrying object. Its enrolled stage 1 is a
small m1n1 that loads stage 2 **from storage** via the `chainload=` variable ->
`chainload_load()` (src/chainload.c) -> `nvme_init()` + `rust_load_image(spec)`.
The embedded-payload object was a Wallace-specific shortcut to avoid needing
storage; it is not a path upstream exercises, and `payload.c:256`'s
"SEPFW after m1n1" plus `chainload_image()`'s explicit SEPFW relocation and
`/chosen/memory-map` rewrite show the enrolled and chainload paths differ in ways
the embedded route never accounted for.

## The pivot worth testing next (cheap, tethered, no enrollment)

`m1n1`'s **own** NVMe driver is not SoC-gated: `src/nvme.c` binds the generic ADT
paths `/arm-io/ans` + `/arm-io/sart-ans` over RTKit. The Linux NVMe blocker is the
SPTM-guarded ABI (tickets 051/052/054/055) — a *Linux* problem. Whether m1n1's
pre-Linux ANS/SART/RTKit path works on T6040 is a **separate, untested question**.

If it works, the standard Asahi architecture becomes available and removes the
object-size problem entirely:

```text
enrolled: small m1n1 (~1 MiB, proven to boot)  +  chosen var chainload=<spec>
   -> m1n1 reads stage 2 (m1n1 + kernel + DTB + Alpine) from storage
   -> untethered boot, no embedded payload, no iBoot size/layout coupling
```

**Test it tethered, with zero risk:** chainload a normal m1n1, then from the proxy
shell drive `nvme_init()` (or a small proxy script) and see whether ANS comes up
and a partition is readable. No enrollment, no boot-policy change, fully
reversible — a wedged link at worst.

Fallbacks if m1n1 NVMe does not work:
1. **USB stage 2** — needs Sol's R3 ATC/HPM host link *and* USB mass-storage +
   FAT support in m1n1, which does not exist (U-Boot has it: ticket 025/B1).
2. Accept tethered chainload as the working configuration and pursue untethered
   later.

Artifacts retained: `Image-b0-diet` (16.8 MiB, 67% smaller, live-proven via
chainload), `initramfs-alpine-b0-nb2.cpio.xz` (Norwegian keymap, live-verified),
m1n1 v2 `5e9dcfd3` (unconditional early-proxy window, live-verified), v3
`c59d5820` (adds FB_CONSOLE_ALWAYS). All are reusable by whatever loader
architecture wins.
