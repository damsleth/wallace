# T6040 DIET_CAPABLE kernel — networking + block capable (2026-07-25)

Ticket 143 (and the kernel half of 145). The plain `DIET=1` kernel drops `CONFIG_NET`
entirely — correct for the B0 RAM root, which runs zero network services — but that blocks
WiFi (139) and the `root=/dev/ram0` rehearsal (145). `DIET_CAPABLE=1` (used together with
`DIET=1`) restores exactly those stacks.

## Result

| Kernel | Raw | XZ |
|---|---|---|
| defconfig-era proven (`Image-hid-type-fix`) | 50.8 MiB | 16.5 MiB (gz) |
| `DIET=1` (B0, proven booting) | 16.8 MiB | 4.68 MiB |
| **`DIET_CAPABLE=1`** (`Image-b0-dietcap`) | **33.7 MiB** | **9.85 MiB** |

Still 34% smaller than defconfig while carrying networking, WiFi, PCIe and block support.

Verified present in the produced config: `ARM64_16K_PAGES`, `PAGE_SIZE_16KB`, `PCIE_APPLE`,
`BRCMFMAC`, `BRCMFMAC_PCIE`, `CFG80211`, `MAC80211`, `NET`, `BLK_DEV_RAM`, `EXT4_FS`,
`MTD_PHRAM`, `FW_LOADER`, `APPLE_DART`, `ARCH_APPLE`, `APPLE_DOCKCHANNEL_HID`,
`DRM_SIMPLEDRM` — and `ARM64_SME` correctly still **off** (SME breaks M4 boot).

## The assertion earned its keep immediately

The first `DIET_CAPABLE` build **failed on purpose**:

```text
== DIET_CAPABLE: assert the networking/block stacks survived ==
  CAPABLE LOST: CONFIG_PCIE_APPLE
DIET config is missing boot essentials; refusing to build
```

Root cause: `PCIE_APPLE` `depends on PAGE_SIZE_16KB`, and `arm64 defconfig` defaults to
**4 KiB** pages. So Apple's PCIe controller requires the native Apple Silicon **16 KiB**
page size. Without the assertion this would have produced a silently PCIe-less kernel and
wasted a rig boot on WiFi later. `DIET_CAPABLE` now sets `ARM64_16K_PAGES` and asserts both
it and `PAGE_SIZE_16KB`.

## ⚠️ Page size differs from the proven B0 kernel

The proven B0 diet kernel is `CONFIG_ARM64_4K_PAGES` / `PAGE_SIZE_4KB`; `DIET_CAPABLE` is
**16 KiB pages**. That is an ABI-level difference, not a config tweak (Asahi kernels use 16K
as standard on Apple Silicon, so 16K is the better-supported choice long term — but it is
untested *here*). A `DIET_CAPABLE` image must therefore be smoke-tested on its own before
being trusted for anything beyond WiFi/PCIe bring-up; do not assume the B0 boot result
transfers.

## Next users of this kernel

- **139 (WiFi)**: PCIe op-115 bring-up must land first (tickets 068/124); then
  `brcmfmac` + the extracted BCM4388 firmware.
- **145 (root rehearsal)**: `root=/dev/ram0` from an ext4 image, exercising the real-root
  path before USB enumeration exists. `BLK_DEV_RAM` is sized to one 512 MiB disk.
