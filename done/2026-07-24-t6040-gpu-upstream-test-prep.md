# T6040 G16 upstream test-mule preparation (2026-07-24)

Ticket 039 (offline, P2, GPU). Current upstream source was refreshed and the
captured J614s hardware/firmware evidence was reduced to a mule-test packet.
There is no safe T6040 GPU candidate today, so no driver was forked, no
G14-compatible alias was invented, and the rig was not touched.

## Current upstream gate

The checkpoint is pinned, not inferred from package versions:

| Surface | Inspected revision | T6040/G16 result |
|---|---|---|
| Asahi Linux `asahi-wip` | `f4dd286f7888b348c757b9a2f28dd7bde4c3532b` (2026-07-15) | no T6040 hardware module/device ID; configurations end at T6022 and `GpuGen::G14`; accepted firmware combinations are G13/G14 with 12.4/13.5 |
| Mesa main | `479773c7e4264506f2d9ec4bf15c6bf677f0d67a` (2026-07-24) | no explicit G15/G16 chip type; `agx_device.c` selects G14G/G14X for every generation ≥14; default renderer identity remains G13/G14 |
| m1n1 upstream | `7c7716b6a196c7e601f9f22bb8af335c1b8173ce` | `dt_set_gpu()` recognizes T8103/T8112/T600x/T602x only; no T6040 calibration/handoff case |
| Asahi M4 feature table | checked 2026-07-24 | GPU for T604x remains **TBA** |

This is a three-surface blocker. A kernel compatible alone would still lack
the G16 firmware ABI and Mesa hardware path. Mesa's current `>= 14` selection
is not evidence that G16 is supported; applying it to generation 16 would
misidentify the hardware as G14. The first candidate must be an explicit,
coordinated T6040/G16 kernel + m1n1 + Mesa branch supplied or endorsed upstream.

Primary status source:
<https://asahilinux.org/docs/platform/feature-support/m4/>.

## Exact J614s evidence packet

Source machine identity is Mac16,8 / J614s / T6040. Sensitive per-machine
identifiers are intentionally excluded.

### ADT

- captured ADT SHA-256:
  `9797cebceff1cbe590955a79fa968220b75fbf2fe6e1756fb223ed3e3794ebe5`
- device-tree tag: `EmbeddedDeviceTrees-11156.120.31`
- `/arm-io/sgx` compatible: `gpu,t6040`
- SGX registers:
  `0x88000000/0x03758000`, `0x88d00000/0x0016c000`
- SGX interrupts:
  1481, 1482, 1483, 1484, 1505, 1507, 1496, 1498
- `/arm-io/gfx-asc` compatible: `iop,ascwrap-v6`
- ASC registers:
  `0x8a600000/0x00088000`, `0x8a050000/0x00060000`
- ASC interrupts: 1502, 1501, 1504, 1503
- performance metadata:
  16 perf states, 2 tables, `gpu-num-perf-states = 15`
- feature metadata:
  `metal-standard = 0x100`, `opengl-standard = 0x300`,
  `agx-address-space-mgmt-mode = 1`, `has-kf = 1`

Reserved regions carried by the ADT:

| Property | Base | Size |
|---|---:|---:|
| `gpu-region` | `0x105fffb8000` | `0x4000` |
| `gfx-handoff` | `0x105fff70000` | `0x4000` |
| `gfx-shared-region` | `0x105fff78000` | `0x40000` |
| `gfx-shared-l2-region` | `0x105fff74000` | `0x4000` |
| `gfx-data` | `0x10001d34000` | `0x138000` |
| `rtkit-private-vm-region` | `0xfffffc0000000000` | `0x2000000000` |

These are inventory inputs, not permission to map or probe the addresses.
The upstream branch owns the correct DT/UAT interpretation.

### Paired firmware source

The exact macOS 26.5.2 build 25F84 kernelcache contains:

- `AGXFirmwareKextG16RTBuddy`;
- `AGXG16X` / `AGXAcceleratorG16X`;
- `gpu,t6040`;
- `RTKit-1558.40.16.release`.

Hashes:

| Object | SHA-256 |
|---|---|
| compressed kernelcache IM4P | `4cc018b4ab925d879a0f039bf1f83cdbd11dc0bd906910afd1f9d15befabad1b` |
| decompressed arm64e kernelcache | `ed556fe62efc2c229f3d4c7ebbbcd21fd5c8d099fbb4d9b5ae636dd78b61d3f6` |

The paired blob proves the generation/build identity, but it is not yet an
upstream-consumable firmware package. Ticket 030 owns broader paired-firmware
collection. When GPU maintainers request a specific extraction format, derive
it reproducibly from this exact object and record the tool/hash; do not guess a
filename or substitute a different macOS build.

## Ready test contract

`docs/t6040-gpu-upstream-smoke.md` is the reusable gate, staged checklist, stop
policy, and report template. It enforces:

1. explicit T6040/G16 support across m1n1, kernel, and Mesa;
2. offline DT/initramfs/source review before any live proposal;
3. storage-disabled `maxcpus=1 idle=nop` RAM-root and one boundary per boot;
4. probe-only G0, userspace-open G1, one bounded submission G2, then a short
   requested conformance smoke G3;
5. immediate stop on SError, DART/GPU/firmware fault, reset, console/display
   loss, or unexpected peripheral probe.

Until the admission gate passes, simpledrm/fbcon is the correct B0/B1 display
path. GPU acceleration is not a blocker for the bootable RAM distro.
