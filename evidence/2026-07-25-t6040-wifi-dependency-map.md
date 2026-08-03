# T6040 WiFi (BCM4388) dependency map — ticket 139 deliverable (2026-07-25)

WiFi is **blocked two layers back**, and one prerequisite has silently expired. Recording
the exact chain so nobody starts at the wrong end.

## The chain, innermost blocker first

| # | Prerequisite | State |
|---|---|---|
| 1 | **PCIe link up (op-115)** | ❌ **negative result.** Ticket 068's clkgen/PLL retest ran 2026-07-24: the PLL *locks*, but the PHY-IP read at `0x417040090` **still hangs**. Verdict was "do not retry unchanged". |
| 2 | An additional pre-`reg[3]` gate/reset/domain operation | ❌ unknown — ticket 124 must find it by **static paired-driver tracing**; explicitly "do not guess offsets, add another write, or repeat the read until a new exact precondition is independently grounded". |
| 3 | **BCM4388 firmware staged** | ❌ **expired.** `/private/tmp/t6040-vendorfw` now contains only `apple/tpmtfw-j614s.bin` (trackpad). The WiFi firmware is gone — `/private/tmp` is ephemeral. Regeneration recipe: `evidence/2026-07-14-t6040-bcm4388-fw-extract.md` (26.x firmware lives inside the `AppleBCMWLAN` dext). |
| 4 | Networking-capable kernel | ✅ **done today** — `Image-b0-dietcap` (33.7 MiB / 9.85 MiB xz) carries `PCIE_APPLE`, `BRCMFMAC`, `BRCMFMAC_PCIE`, `CFG80211`, `MAC80211`, `NET`, `FW_LOADER`, `APPLE_DART`. See `evidence/2026-07-25-t6040-dietcap-kernel.md`. |
| 5 | `brcmfmac` binds + firmware loads | not reachable until 1-3 |
| 6 | `wpa_supplicant`/`iw` in the distro image | trivial once 5 works (Alpine packages; musl-clean) |

## Consequence for sequencing

WiFi cannot progress by working on WiFi. The single actionable item is **ticket 124's static
PCIe tracing** — find the missing precondition before `reg[3]`. That mirrors the USB
situation exactly: both fronts are gated on static reverse-engineering, not on more boots.

A useful datum discovered while building the capable kernel: **`PCIE_APPLE` requires 16 KiB
pages** (`depends on PAGE_SIZE_16KB`), while the proven B0 kernel is 4 KiB. So any
PCIe-enabled boot is also a page-size change and must be smoke-tested on its own terms.

## Immediately actionable, low cost

- **Re-stage the BCM4388 firmware** so prerequisite 3 stops being a hidden landmine, and put
  it somewhere non-ephemeral this time (`/private/tmp` does not survive). This needs the
  25F84 IPSW/dext corpus per the extract recipe.
- Keep `DIET_CAPABLE` as the kernel for all PCIe/WiFi experiments.

## Not recommended

Attempting `brcmfmac` before PCIe links up, or repeating the op-115 read: ticket 068 already
established the negative result and asked for grounded evidence rather than another attempt.
