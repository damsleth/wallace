# Stage B item 5 — T6040 kboot FDT init

Written 2026-07-10, after ATC/USB/DART audit (item 4). Companion: `docs/ROADMAP.md`,
`docs/t6040-dt-checklist.md`. Item 5 = m1n1's kboot→FDT handoff: patch the kernel DT
with runtime info (carveouts, tunables, MPIDR/release-addr, firmware) before
jumping to Linux.

## The overarching constraint: item 5 is Stage-C-coupled

`kboot_prepare_dt()` (kboot.c:2749) patches an **input kernel FDT** — it needs a
linux-asahi **t6040 devicetree** (Stage C) to run against, which doesn't exist
yet. So all of item 5 is:
- **kboot-only** — not exercised at m1n1 boot, not chainload-testable.
- **FDT-only** — reads ADT, writes the in-memory DT. **No hardware MMIO → safe.**
- **testable only incrementally against Stage C** (per the roadmap).

Approach: fix the parts verifiable *now* from the ADT; audit the rest; defer what
genuinely needs the kernel DT. Don't write blind kboot code for its own sake.

## Landscape (kboot_prepare_dt runs ~30 dt_set_* fns)

Most are generic (ADT→FDT, chip-agnostic) and need nothing for t6040. Audited:

| Area | t6040 status |
|---|---|
| `dt_set_cpus` (MPIDR + `cpu-release-addr` spin-table) | ✅ generic — SMP already works; release-addr from `smp_get_release_addr` |
| DART nodes (`dt_get_iommu_node`, `dt_init_dart_by_node`) | ✅ generic — t6040 DARTs are `dart,t8110` (supported) |
| `dt_set_acio_tunables` (USB4 rc/pcie_adapter) | ✅ works (item 4 audit) |
| `dt_set_display` (framebuffer/DCP carveouts) | **⛔ was missing t6040 → FIXED here** |
| `dt_set_sep`, `dt_set_pmp`, `dt_set_isp_fwdata`, `dt_reserve_asc_firmware` | generic ADT-driven — verify at Stage C |
| `dt_set_gpu` (GPU carveout) | Stage F (drm/asahi); out of scope here |
| compat fixup (`dt_fixup_t6020_compat`) | speculative for t6040 — see below |

## FIXED this session — `dt_set_display` t6040 branch

**Gap:** `dt_set_display` picks a per-chip `disp_reserved_regions_*` table by
compatible; t6040 hit the final `else` → "unknown compatible, skip display
reserved-memory setup" → **no display carveouts handed to the kernel** → DCP/disp0
would fail at Stage C.

**Fix (verified, not guessed):** fold `apple,t6040` into the t6020/t6021 branch,
reusing `disp_reserved_regions_t602x`, and add t6040 to the
`dt_reserve_dcpext_firmware` group. Justification — live ADT
`/chosen/carveout-memory-map` (2026-07-10):

| region-id | role (t602x table) | t6040 base / size |
|---|---|---|
| 49 | asc-firmware | 0x100002e4000 / 0x6d0000 |
| 50 | dcp_data | 0x105d2c60000 / 0x2c4000 |
| 57 | region57 | 0x105d8b5c000 / 0x1000000 |
| 94 | region94 (dcp+disp) | 0x105d87fc000 / 0x360000 |
| 95 | region95 (disp piodma) | 0x105d873c000 / 0xc0000 |
| 157 | region157 (dcp+disp) | 0x105d2f88000 / 0x4000 |
| 14 | (framebuffer anchor) | 0x105d2f90000 / 0x57ac000 |

Every t602x display region-id exists on t6040 with display-plausible sizes,
clustered around the framebuffer — a structural match, so the t602x table is the
correct reuse. FDT-only, so zero hardware risk even though untested until Stage C.

**Open (Stage C validation):** t6040 also has dcpext0/1 data regions (region-id
73/74 and 88/89 — dcpext2-7 absent, so 2 external controllers). The t602x path
reserves dcpext *firmware* (via `dt_reserve_dcpext_firmware`) but does NOT
statically carve those data regions (unlike the t600x path, which uses
`dcpext_reserved_regions_t600x[]`). Whether M4 DCP firmware needs them explicitly
carved is a Stage-C question — if dcpext displays misbehave, add a t6040 dcpext
carveout table using 73/74 + 88/89.

## Deferred (needs the kernel DT / later stages)

- **Compatible fixup:** `dt_fixup_t6020_compat` (kboot_t6020_compat.c) appends
  generic `apple,*` compatibles to `apple,t6020-*` nodes for old Linux drivers —
  a transition-era shim. Whether t6040 needs an analogue depends entirely on how
  the (not-yet-existing) linux-asahi t6040 DT names its nodes. **Don't write a
  speculative `dt_fixup_t6040_compat`** — add it (if needed) once a real t6040 DT
  exists and a driver fails to bind. Documented, not coded.
- **GPU carveout** (`dt_set_gpu`): Stage F.
- **ISP/SEP/SMC/PMP/PMGR:** generic ADT-driven; verify (don't pre-patch) at Stage C.

## Exit
- `dt_set_display` no longer skips t6040; display carveouts derived from the
  verified t602x region scheme. Rest of item 5 audited: generic parts OK,
  speculative/Stage-F parts deferred with rationale.
- Real validation is Stage C (linux-asahi t6040 DT boot). Nothing here does MMIO.

## References
- `src/kboot.c`: `kboot_prepare_dt` :2749, `dt_set_display` :1935 (+t6040 branch),
  `dt_reserve_dcpext_firmware` :1820, `disp_reserved_regions_t602x` :1924,
  `dt_set_cpus` :541. `src/kboot_t6020_compat.c` (compat shim).
- ADT carveout map cross-ref: `t6041-mcc-adt-layout` (same node), framebuffer
  region-id-14. Template: t602x (M2 Pro/Max) display path.
