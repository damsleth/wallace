# T6040 U-Boot no-MMIO preparation

Date: 2026-07-23  
Ticket: 025  
Scope: B1 host preparation; no rig, enrollment, APFS, or Boot Policy work

## Result

Prepared and host-built an upstream-shaped T6040 first-light U-Boot patch:

```text
patches/uboot-t6040-noio-prep.patch
SHA-256 7555aec41d86d6edb58a3e593199ed4b81b40be1316700c7c03ddf1d183963b5
```

It is deliberately not a normal device-enabled U-Boot target. It maps only
runtime DT-derived RAM and the m1n1-provided framebuffer, compiles the EFI
loader and built-in `bootefi hello` application, and stops at the prompt with
autoboot disabled. It contains no T6040 MMIO address and enables no bus driver.

This is B1 preparation after B0. It is not required by, and must not delay, the
direct-m1n1 Alpine milestone.

## Upstream baseline audit

Source:

```text
AsahiLinux/u-boot branch asahi
commit 8aa706b2daa49b64102e44067d8514de8a26dc42
```

The unmodified `apple_m1_defconfig` builds successfully and already provides:

- an ARM64 Image header in `u-boot-nodtb.bin`;
- position-independent execution at text base zero;
- `board_fdt_blob_setup()` returning the DT pointer m1n1 passed in `x0`;
- simple framebuffer output;
- EFI loader, EFI boot manager, and `BOOTAA64.EFI` discovery;
- FIT creation/listing tools.

However, it cannot run on J614s:

1. `build_mem_map()` knows only t8103/t8112, t600x, and t602x and panics
   `Unsupported SoC` for `apple,t6040`.
2. `ARCH_APPLE` selects PCIe, NVMe, USB, IOMMU, PMGR, input, watchdog, and
   other MMIO-backed frameworks.
3. Its default command is `bootflow scan -b` after two seconds, which would
   immediately probe storage paths.
4. Its Apple board helpers call NVMe namespace scanning unconditionally.

The normal target is therefore neither compatible nor an acceptable
first-light artifact.

## Draft patch contents

The patch adds:

- `CONFIG_APPLE_NOIO`, making Apple bus/MMIO framework selections conditional;
- a T6040 memory-map array with only two empty slots:
  - RAM, filled from the m1n1-fixed `/memory` node;
  - framebuffer, filled from `/chosen/framebuffer`;
- compile guards around the Apple NVMe environment helpers;
- `apple_t6040_noio_defconfig` with:
  - `CONFIG_BOOTDELAY=-1`;
  - empty `CONFIG_BOOTCOMMAND`;
  - EFI loader, `bootefi`, and built-in EFI hello test;
  - simple framebuffer;
  - no S5L serial driver.

The resulting configuration explicitly has PCI, NVMe, USB, WDT, Apple DART,
Apple PMGR, Apple PCIe, Apple ATC, Apple mailbox/input, and Apple SPI support
unset. Generic BLK is selected only because U-Boot's EFI loader requires the
block uclass; no block controller is compiled.

The patch applies cleanly to the exact upstream commit and `git diff --check`
passes.

## Reproducible host build

Build environment: native arm64 Debian bookworm container, with
`SOURCE_DATE_EPOCH=1784764800`.

```sh
make apple_t6040_noio_defconfig
make -j6
```

Two clean builds were byte-identical:

| Output | Bytes | SHA-256 |
|---|---:|---|
| `.config` | — | `13ca83cd45606fbfc3aa05ca00f9acb7201fc85dcf15ec7caadbb19422675f6a` |
| `u-boot-nodtb.bin` | 492,624 | `f2f46cbc7dfbe8b82866859810939bdec49f26fcdd397ac29f7d2357b5853db9` |
| `helloworld.efi` | 16,561 | `1750b7c26df955689a78dd151c0064c974e27b695c955cf2483b6d28ea88210c` |

`u-boot-nodtb.bin` has `ARM\x64` at offset `0x38`, text offset zero,
Image flags `0xa`, and Image runtime size 976,280 bytes.

## Raw m1n1 payload detail

The U-Boot binary must be the **last** m1n1 payload, after the J614s DTB. A raw
ARM64 payload has no stored-file length, so m1n1 treats it as the final kernel
and copies the Image header's complete `image_size`.

The file is only 492,624 bytes while its header declares 976,280 bytes.
Therefore a raw object must append exactly 483,656 zero bytes after
`u-boot-nodtb.bin`. Without that padding, m1n1 would copy beyond the supplied
object. This differs from ticket 080's B0 layout, where a compressed Linux
kernel supplies an exact member length.

An in-memory-only layout check used the live-proven no-PCIe-write m1n1 and the
diagnostic J614s DTB:

| Record | Offset | Size |
|---|---:|---:|
| m1n1 | `0x000000` | 1,097,728 |
| raw FDT | `0x10c000` | 51,659 |
| U-Boot file | `0x1189cb` | 492,624 |
| U-Boot zero reserve | follows file | 483,656 |

Complete size: 2,125,667 bytes. Test-vector SHA-256:
`4c1d236cc9411ccd4f11348f03ee5b341da8e4e69dff5e056619b1120ea40f12`.
It was never written and is not a rig artifact.

## FIT and EFI host checks

The baseline U-Boot `mkimage` tool created the current diagnostic
kernel+DTB+initramfs as a FIT twice with fixed
`SOURCE_DATE_EPOCH=1784764800`. The files were byte-identical:

```text
size    57,400,126
SHA-256 d96c020cb93f70fe1aa3c9fe01bd6926662ed2549b67dde4cb4740cae8c05c1d
```

`dumpimage -l` found one arm64 Linux kernel, the exact J614s FDT, the exact
gzip initramfs, and a default configuration linking all three. This is only a
format/toolchain fixture; its zero load/entry fields and diagnostic Linux
inputs are not a release artifact.

The no-I/O build also compiles the standard EFI hello application and embeds
the `bootefi hello` command. A later live sequence can therefore separate:

1. U-Boot banner/prompt with no autoboot or device probing;
2. automatic built-in EFI hello execution, still with no storage;
3. only after those pass, a reviewed storage/bootflow driver path.

## Remaining gates

Ticket 025's offline preparation is complete. Before any live run:

- B0 must pass first;
- the patch and exact source/config/binary/DT/m1n1 hashes need independent
  review;
- a separate one-shot rig ticket and explicit approval are required;
- first proof must retain no-MMIO configuration and framebuffer-only output;
- the U-Boot Image-size zero padding must be verified;
- KIS may observe m1n1, but U-Boot success cannot depend on a host command.

The ordinary EFI-from-disk flow remains blocked on a safe readable storage
path: internal NVMe has the documented raw-boot SPTM boundary, and external USB
still lacks T6040 HPM/ATC link support. Neither blocker is bypassed here.

No patch was posted externally.
