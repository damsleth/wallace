# Stage B item 4 — T6040 ATC / USB tunables + DART (kernel handoff)

Written 2026-07-10, after PCIe (item 3). Companion: `docs/ROADMAP.md`, the pcie plan.
Item 4 = the kboot→FDT handoff for Type-C/USB: ATC PHY tunables, USB4/ACIO
(Thunderbolt) tunables, apciec (TB PCIe), and DART config.

## TL;DR — this item is mostly "verify + defer", not "write code"

All of item 4 runs **only at kboot** (`kboot.c:2795-2799`: `kboot_setup_atc`,
`dt_set_acio_tunables`, `dt_set_pcie_tunables`) — NOT at m1n1 boot, so it's not
chainload-testable. But unlike PCIe it is **FDT-only (no hardware MMIO)** → safe.
After a full ADT audit on the live M4, the breakdown is:

| Piece | t6040 status | Action |
|---|---|---|
| **DART** | ✅ works — all DARTs are `dart,t8110`, fully supported in dart.c; works at boot; kboot handling is compatible-string generic | none (done) |
| **ACIO USB4 rc + pcie_adapter** | ✅ property names present on `acio0` | none (works as-is) |
| **ACIO USB4 NHI** | ⚠️ partial — has merge+fw_int, missing tx/rx desc/data/wr fabric | defer (Thunderbolt, Stage D+) |
| **apciec (TB PCIe)** | ⚠️ different tunable prop names | defer (Thunderbolt, Stage D+) |
| **ATC PHY tunables** | ⛔ blocked on reg-bucket offsets (new t6040 PHY map) | document + watch upstream |

**No code landed this session** — the correct outcome. The fuse-table entry is
inert (the cleanup path wipes `apple,tunable-common-a` on any tunable failure),
the ATC tunable table is blocked (below), and DART/ACIO-rc already work.
Speculative code here would be wrong (advisor-confirmed).

## Does this block the milestone? No.

Stage C's exit (initramfs shell over USB-gadget/serial) needs only **USB2**. When
ATC tunable setup fails, `dt_copy_atc_tunables`' cleanup path (kboot_atc.c:491)
strips the half-filled properties and the machine boots **USB2-only** — keyboard,
serial, basic USB all fine. ATC tunables buy USB3 + Thunderbolt = a **Stage D**
comfort. Deferring is legitimate scoping, not a hole.

## Live ADT audit (2026-07-10)

- **atc-phy0..3** = `atc-phy,t6040` (4 PHYs). No t8122/t6020 fallback compat.
- **usb-drd0..2** = `usb-drd,t6040` + `usb-drd,t8132` (dual — kernel matches t8132).
- **dart-usb0..2, dart-acio*, dart-apciec*** = `dart,t8110`.
- **acio0..2** = `acio,v2`; **apciec0..2** = `apciec,t6040`.

## ATC PHY tunables — what's blocked and what's NOT

`kboot_setup_atc` → `dt_copy_atc_tunables` per atc-phy node: copies ADT
`tunable_*` props into FDT `apple,tunable-*` buckets. Current code picks the
`atc_tunables_t8122` set only for `atc-phy,t8122`, else the default set. t6040
matches neither → default set → most required tunables' ADT names don't exist on
t6040 → graceful fail → USB2-only.

**NOT blocked: the FDT bucket names.** Both existing tables emit the same
`apple,tunable-{axi2af,common-a,common-b,lane0/1-usb/cio/dp}` buckets — verified.
So the kernel-side name contract is stable; a `atc_tunables_t6040` table would use
the same bucket names.

**Blocked: the per-bucket `reg_offset`/`reg_size`.** Each table entry maps an ADT
source tunable → an FDT bucket at a `reg_offset` within that bucket's PHY sub-block
(e.g. where `CIO3PLL_CORE` sits inside `-common-b` at 0x2a00). t6040's PHY register
map is new (`CIO4PLL` not `CIO3PLL`, etc.), so these bases must be RE'd from the
t6040 atcphy register layout — they are NOT derivable from the ADT (the ADT
tunable's offset is *within* the bucket; the bucket base is the unknown). Inventing
a base = kernel programs wrong PHY registers. **Document, don't guess.**

### t6040 atc-phy0 ADT tunable inventory (seed data for the future table)

Source `tunable_*` props (name → entry count), decoded from the live ADT — the
raw material a `atc_tunables_t6040` table must map to FDT buckets:

- `tunable_ATC0AXI2AF` (55), `tunable_ATC0AXI2AF_LIOA` (3) — → `-axi2af`
- `tunable_ATC_FABRIC` (48), `tunable_ATC_COMMON_CFG` (0) — → `-common-b`
- `tunable_AUSPLL_CORE` (4), `tunable_AUS40CMN_SHM` (0) — → `-common-b`
- `tunable_CIO4PLL_CORE` (3) — → `-common-b` (was `CIO3PLL_CORE` on older)
- `tunable_LN{0,1}_RX_CFG_TX_OF_RXCLK` (3 each), `..._RX_EQ_CIO_DFLT`,
  `..._RX_TOP_CIO_DFLT`, `tunable_UC_REGS_CIO_DFLT` — → `-lane{0,1}-{usb,cio}`
- `tunable_USB2PHY_{DEV,HOST,DFLT}`, `tunable-device`, `tunable-host` — USB2 PHY
- (Many read 0 entries on this unit — likely per-port/unpopulated-lane variance.)

New source names vs older chips: `CIO4PLL_CORE`, `AUS40CMN_SHM`, `ATC_COMMON_CFG`,
`ATC0AXI2AF_LIOA`, `LN{0,1}_RX_*`, `UC_REGS_CIO_DFLT`, `USB2PHY_*`.

### Upstream watch

Correction 2026-07-23: `upstream/atcphy-new-tunables` still exists at
`9657a52e`, but it has not moved since 2025-01-16 and is 353 commits behind
current m1n1 main. It is not an active T6040 implementation. Current main has
newer T8122 handling but still no T6040 table/fuse entry, and published Linux
ATC branches have no T6040 compatible. Track the broader upstream work and
#asahi-dev rather than that branch alone. Exact refresh:
`done/2026-07-23-t6040-atcphy-upstream-checkpoint.md`.

## Next steps (when unblocking)

1. Get the t6040 atcphy register map (bucket bases) from upstream RE / a
   linux-asahi t6040 atc-phy driver + DTS, or careful gated RE at Stage C+.
2. Add `atc_tunables_t6040` (same FDT buckets, t6040 source names + RE'd offsets)
   and route `atc-phy,t6040` to it; add an empty-fuse entry for `atc-phy,t6040`.
3. Thunderbolt (Stage D+): t6040 NHI + apciec tunable-name mapping.

## References
- `src/kboot_atc.c`: `atc_fuses` :280, `atc_tunables` :31, `atc_tunables_t8122`
  :64, `dt_copy_atc_tunables` :417 (cleanup :491), `kboot_setup_atc` :505.
- `src/kboot.c`: `dt_set_acio_tunables` :1241, apciec :1331, DART :1358+.
- `src/dart.c`: `dart,t8110` support :301. Template: t8122/t6031 ATC family.
