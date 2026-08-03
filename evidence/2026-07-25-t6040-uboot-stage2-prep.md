# T6040 U-Boot stage-2 USB loader preparation

Date: 2026-07-25  
Ticket: 128 (follow-up to 025's no-IO prep of 2026-07-23)  
Scope: offline analysis + reviewable build. No rig, lease, boot, enrollment,
kmutil/bputil, APFS, or Boot Policy action. Nothing was posted externally.

## Why this exists

Both enrolled-untethered routes died on 2026-07-25: the appended-payload shape
can never be discovered (m1n1's payload scan lands inside its own image,
`evidence/2026-07-25-t6040-enrolled-payload-rootcause.md`), and `chainload=` from
internal NVMe dies in m1n1's own `nvme_init()` with the async L2C SError
(`evidence/2026-07-25-t6040-nvme-probe-result.md`). The remaining untethered shape
is a small enrolled loader that reads stage 2 from a FAT32 USB stick. m1n1 has
no USB mass-storage or filesystem code; U-Boot has both. This task answers
whether U-Boot can also solve the *port bring-up* problem, and prepares the
stage-2 U-Boot either way.

## 1. The pivotal question: can U-Boot bring a Type-C port to host mode itself?

**NO.** Upstream (Asahi) U-Boot contains no Type-C PHY logic and no HPM/USB-PD
driver of any kind. Evidence from the pinned tree
(`AsahiLinux/u-boot` branch `asahi`, commit
`8aa706b2daa49b64102e44067d8514de8a26dc42`):

- `drivers/phy/phy-apple-atc.c` is the *only* Apple PHY file and is 55 lines:
  an **empty** ops table (`static const struct phy_ops apple_atcphy_ops = {};`)
  plus a reset controller whose `of_xlate` accepts and does nothing. It
  performs zero MMIO. Its own Kconfig entry (`drivers/phy/Kconfig`,
  `config APPLE_ATCPHY`) says it outright:
  *"This is a dummy driver since the PHY is initialized sufficiently by
  previous stage firmware."*
- A tree-wide search for an HPM/USB-PD/Type-C manager driver
  (`tps6598x`, `cd321x`, `tipd`, `hpm`, `typec`) finds nothing — U-Boot has no
  code that can talk to the SN2012020 HPM2 on `nub-spmi-a1`, and no SPMI
  controller driver at all.
- The Apple USB path is generic `xhci-dwc3` (`drivers/usb/host/xhci-dwc3.c`,
  binds `snps,dwc3`): it sets the DWC3 core's `dr_mode` to host and registers
  xHCI. Everything upstream of the DWC3 core — Type-C CC negotiation, mux and
  orientation, eUSB2 repeater, ATC PHY lane configuration, VBUS — is assumed
  to be already in place.
- `arch/arm/mach-apple/board.c` contains no USB, ATC, or HPM handling.

Why it still works on M1/M2: previous stages leave those ports host-capable —
the I2C-attached TPS6598x/CD321x HPMs autonomously handle CC, and m1n1
performs `usb_init()` PHY bring-up. On M3/M4 m1n1 explicitly does **less**:
`m1n1 src/usb.c usb_init()` takes the SPMI branch
(`/arm-io/nub-spmi-a0/hpm0` probe) and "just brings up the phys" — it never
touches the SPMI HPMs. And on T6040 we have live proof the inherited state is
*not* host-capable: the reviewed right-port Linux smoke produced healthy root
hubs and zero device detection
(`evidence/2026-07-21-t6040-usb-right-no-connect-analysis.md`), because nothing
performs the HPM2 host transition, which is itself a final **NO-GO**
(ticket 096, `evidence/2026-07-24-t6040-hpm2-detach-static-slice.md`).

**Consequence, stated plainly: U-Boot inherits exactly the same HPM/ATC
dependency as Linux. Building U-Boot does not unlock USB enumeration on
T6040. Untethered-via-USB remains blocked behind the R3 host-link work
(tickets 096/097), which is currently NO-GO.** No design in this prep routes
around that: the artifact contains no SPMI, PMU, charger, NVRAM, or firmware
write of any kind.

What U-Boot *does* solve — the entire layer m1n1 lacks: xHCI host stack, USB
mass-storage (BOT), partition tables, FAT, and a scripted kernel+DTB+initramfs
boot. Once (and only once) a proven, maintainer-approved host transition
exists — architecturally it belongs in stage 1 (m1n1) before the handoff,
mirroring how every other Apple platform works — this stage-2 build is the
missing rest of the untethered chain.

## 2. Design of the stage-2 target

Delta patch on top of the pinned commit + the existing no-IO patch
(`patches/uboot-t6040-noio-prep.patch`,
`7555aec41d86d6edb58a3e593199ed4b81b40be1316700c7c03ddf1d183963b5`):

```text
patches/uboot-t6040-stage2-prep.patch
SHA-256 814ffa47d6ab4b8f050505b879bb21bc730c57c3d89fb75af36a27061b7695c7
```

Design decisions, and why:

- **`CONFIG_APPLE_T6040_STAGE2`, opt-in on top of `APPLE_NOIO`.** The no-IO
  posture (nothing selected by default, no autoboot, no serial, fb console)
  stays the baseline; stage 2 re-enables an explicit allowlist only.
- **No hardcoded MMIO, no static SoC map.** `build_mem_map()` gains a fixed
  pool of device slots filled at runtime from the m1n1-passed DT, and only
  for three allowlisted compatibles:
  `apple,t8103-pmgr` (the four PMGR syscon blocks),
  `apple,t8110-dart` (USB DARTs), and
  `snps,dwc3` (DWC3/xHCI core, plus the Apple wrapper reg that rides in the
  same node). Disabled (`status`) nodes are skipped. Everything else in the
  DT stays *unmapped at the MMU*, so even a misbehaving probe faults on
  translation instead of reaching the fabric — ANS/SART can not be touched by
  construction (NVMe is not compiled in either).
- **Drivers enabled** (all upstream, unmodified): `USB_XHCI_HCD` +
  `USB_XHCI_DWC3` + `USB_DWC3` (core init helpers), `IOMMU` + `APPLE_DART`
  (t8110-dart compatible is already supported upstream), `POWER_DOMAIN` +
  `APPLE_PMGR_POWER_DOMAIN` + `REGMAP`/`SYSCON`/`DM_RESET` (the pwrstate
  driver binds a reset child), `USB_STORAGE`, `FS_FAT` + `CMD_FAT` +
  `CMD_FS_GENERIC` + `CMD_PART` (DOS + EFI partition tables), `CMD_USB`.
  Everything the fault history says to avoid stays absent: **no NVMe, no
  PCIe, no WDT, no SPI/MTP input, no serial driver, no SMBIOS** (verified in
  the final `.config`).
- **Safety calibration from live evidence:** the exact blocks this build can
  touch (PMGR pwrstate regs, `usb2_dart0/1`, `usb_drd2`) are the ones the
  approved ticket-063 Linux smoke already initialized on this machine without
  a fault; the M4 async-SError family (dart-aop/dart-pmp/dart-isp0, ANS/SART)
  is neither mapped nor compiled.
- **Autoboot stays OFF** (`CONFIG_BOOTDELAY=-1`). `CONFIG_BOOTCOMMAND` is
  baked but never runs unattended; it documents the intended flow and can be
  invoked (`boot`) once interactive input exists, or run from `PREBOOT` in a
  future explicitly-approved variant:

  ```text
  usb start && load usb 0:1 ${kernel_addr_r} /boot/Image &&
  load usb 0:1 ${fdt_addr_r} /boot/j614s.dtb &&
  load usb 0:1 ${ramdisk_addr_r} /boot/initramfs &&
  booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
  ```

  The load addresses come from `board_late_init()`'s existing LMB
  allocations (upstream code). `${filesize}` after the last `load` is the
  initramfs size, which is what `booti` needs.
- **EFI hello self-test retained** from the no-IO target, so the proven
  first-light sequence stays available in this binary.

### Expected mapped windows with the J614s stage-2 DT

| Node | Windows |
|---|---|
| pmgr0..3 | `0x288e80000/0x4000`, `0x502280000/0x14000`, `0x502800000/0xc000`, `0x508300000/0x4000` |
| usb2_dart0/1 | `0x392f00000/0xc000`, `0x392f80000/0xc000` |
| usb_drd2 | `0x392280000/0xcd00`, `0x39228cd00/0x3200` |

Eight windows, ~24 slots available; RAM and framebuffer fill the final two
slots exactly as in the no-IO target.

### DT variant

`dts/t6040-j614s-dcuart-uboot-stage2.dts` — U-Boot-only sibling of the
reviewed `usb-host-right` Linux variant (same port choice: `usb_drd2` =
right; DebugUSB's `usb_drd0` stays disabled so a tethered session is never
disturbed). Differences exist only because U-Boot binds different
compatibles: `snps,dwc3` fallback appended (reg[0] is already the DWC3 core),
`dr_mode = "host"` (read directly by xhci-dwc3), and the generic
`apple,pmgr-pwrstate` fallback appended along the exact `atc2_usb` power
ancestry (`atc2_usb`, `atc2_common`, `atc2_usb_aon`, `fab2_soc`, `afi`) —
U-Boot's pmgr driver matches only the generic compatible, which the
generated `t6040-pmgr.dtsi` nodes do not carry.

A host `cpp`+`dtc` compile check passes
(fixture `759d00ba8983d856ef621a4bffae8b16e7fa40db90fdad2628ec7a768bcd7656`,
51,727 bytes — compile check only; any rig artifact must be rebuilt through
the standard kbuild container flow like every other boot DTB).

## 3. Reproducible build

Environment: `debian:bookworm` arm64 container (podman), gcc 12 native
build, `SOURCE_DATE_EPOCH=1784764800` — the same recipe as the no-IO prep
(`helloworld.efi` reproduced bit-identical to the 2026-07-23 artifact,
`1750b7c2…`, confirming the environment matches).

```sh
make apple_t6040_stage2_defconfig
make -j6
```

Two clean out-of-tree builds were byte-identical (`cmp` clean):

| Output | Bytes | SHA-256 |
|---|---:|---|
| `.config` | — | `efd9ab2af71ee681761953faca4728f64e02e798a85910119b872e443d5d716b` |
| `u-boot-nodtb.bin` | 550,584 | `2da75ecdf1000cea1af158dc8dbe69ee4a380d7674c3a797186e606215fec846` |
| `configs/apple_t6040_stage2_defconfig` | — | `846b31783951e54d4d6fe0da58f257cd976ff8328d9685ea9b2309474ef9da1d` |

The defconfig is `savedefconfig`-normalized and round-trips to the same
`.config`/binary.

## 4. Delivery preflight (tethered m1n1 chainload — NOT run, NOT scheduled)

Any first live test is a **tethered chainload over the working KIS/USB-gadget
proxy** — the payload path that is live-proven — proposed as its own rig
ticket with maintainer plan approval and independent exact-artifact review.
This document is preparation, not authorization.

Payload layout rules (from the no-IO prep, unchanged): the U-Boot binary is a
raw ARM64 Image and must be the **last** payload after the stage-2 DTB, padded
with zeros from file size to the Image header's declared runtime size —
for this binary `1,031,720 − 550,584 = 481,136` zero bytes. m1n1
copies `image_size` bytes; without the padding it copies trailing garbage.

Proposed live sequence (each step its own pass gate, fb-console evidence):

1. **Inert banner (this artifact as-is).** Chainload m1n1 + stage-2 DTB +
   padded U-Boot. Pass: U-Boot banner and model line on the panel, prompt
   reached (autoboot off ⇒ nothing else runs), no SError/panic, and after
   power-cycle the enrolled bare loader + proxy come back untouched.
2. **USB probe variant (separate one-line config delta, own review).** Same
   binary plus `CONFIG_PREBOOT="usb info; usb start; usb tree"`. Pass: xHCI
   registers, PMGR/DART/DWC3 probe without fault, root hubs appear, and —
   expected until R3 — **zero devices found**. A powered/passive stick may be
   attached per the existing 108-series fixture rules; no block read, no
   mount, no write.
3. **Full bootcmd** only after the R3 host link exists and 108/109-class
   enumeration+read gates pass under Linux rules; not schedulable today.

Stop conditions (any ⇒ stop, record, release `--state wedged` if the link is
in doubt): SError/exception/panic on the panel; freeze before the banner;
any storage or NVMe-related output (must be impossible — not compiled);
panel dead >60 s after jump; proxy fails to return after power-cycle
(→ DebugUSB recovery per COORDINATION.md).

Explicitly out of scope forever for this artifact: enrollment of any form,
SPMI/PMU/charger/NVRAM writes, Boot Policy/APFS actions.

## 5. Honest dependency statement

- **Needs R3? YES — for its actual purpose.** No USB stick will enumerate
  until the HPM2 host transition (+ any eUSB2 repeater/ATC host-tunable
  bring-up beyond it) is proven and approved. That work is tickets 096/097
  and is presently NO-GO with no safe rollback artifact. U-Boot does not and
  cannot substitute for it; it has no SPMI stack at all.
- **Worth having anyway? Yes, narrowly.** It is the entire stage-2 loader
  layer (MSC/FAT/bootcmd) that m1n1 lacks, prepared and reproducible now; it
  converts "R3 lands" into "untethered chain is complete" instead of "start
  writing a loader". Steps 1–2 above are also independently useful: they
  prove the U-Boot USB stack on T6040 is inert-safe before anyone depends
  on it.
- **Not a milestone dependency.** Nothing in the direct-m1n1/Alpine track
  waits on this.

## Artifacts

| File | SHA-256 |
|---|---|
| `patches/uboot-t6040-stage2-prep.patch` | `814ffa47d6ab4b8f050505b879bb21bc730c57c3d89fb75af36a27061b7695c7` |
| `dts/t6040-j614s-dcuart-uboot-stage2.dts` | `72b58e626170ee84b68f7d0823799559112f3a2061615f25828ded78c3299413` |
| `u-boot-nodtb.bin` (build output, not committed) | `2da75ecdf1000cea1af158dc8dbe69ee4a380d7674c3a797186e606215fec846` |

Base: `AsahiLinux/u-boot` `asahi` @ `8aa706b2daa49b64102e44067d8514de8a26dc42`
+ `uboot-t6040-noio-prep.patch` (`7555aec4…`) + this patch.
