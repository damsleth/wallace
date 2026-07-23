# T6040 PCIe port-0 (BCM4388) stage — pre-review (ticket 044, 2026-07-23)

Pre-reviews the PCIe **port-0** subset of the write manifest
`done/2026-07-14-t6040-pcie-write-manifest.tsv` (source ADT SHA
`87f5c391…`), the stage that runs **after** the shared-PHY prefix and PHY-IP
tunables complete. Gated behind ticket **068** (op-115 clkgen-PLL read must first
prove the PHY-IP aperture is live) **and** the full PHY block (ops 115–351)
completing on the rig. Pre-reviewed now so it is ready when link-up is reachable.

## Target (from `done/2026-07-14-t6040-wireless-pcie-map.md`)

- **Port 0 = `pci-bridge0` = BCM4388 WiFi (`14e4:4434`) + Bluetooth (`14e4:5f72`)**;
  Gen2; DART `0x410000000`, IRQ 1724; **PERST# = GPIO 4**, CLKREQ# = GPIO 0 fn 2.
- Linux-visible port registers use the **T602x layout**: PERST at `0x82c`,
  RID2SID at `0x3000`, MSIMAP at `0x3800` (within the port-0 aperture base
  `0x410028000`/`0x41002b000`/`0x41002b800`).

## Manifest subset audited — ops 352–961 (port0), 610 operations

Category breakdown (col 3):

- `T6031 AXI control` ×1 (`0x416000600` CLEAR 0x10000), `T8122 port init` ×19
  (`0x41002808x/0x410281xx`), `T8122 port PHY control` ×1.
- Tunables (ADT props, applied to the port aperture): `apcie-config-tunables`,
  `pcie-rc-tunables`, `pcie-rc-gen3/gen4-shadow-tunables`.
- `port PHY clear clock requests` / `CLK0REQ` / `CLK1REQ` / `port PHY control` ×2.
- **`RID2SID clear` ×16** (`0x41002b000`+, the stream-ID map) and **`MSIMAP clear`
  ×512 + `MSIMAP vector` ×32** (`0x41002b800`+).
- Link bring-up: `DesignWare 1-lane mode` / `link width 1` / `speed change`,
  `PCIe LNKCAP/LNKCAP2/LNKCTL2` speed+width, `DBI read-only write enable/disable`,
  `APPCLK enable`, `Intr2AXI enable`, **`PERST# deassert` ×1**, `RC post-link
  control`, `T6031 post-link control`.

## Review findings

1. **Addresses ADT-derived.** All port-0 MMIO is inside the port-0 apertures
   (`0x41002xxxx` port block, `0x416000600` AXI, config/DBI space) — reproduced
   from the committed ADT (`87f5c391…`) by `t6040-pcie-write-plan.py`, not
   invented. RID2SID/MSIMAP/PERST offsets (`0x3000`/`0x3800`/`0x82c`) match the
   T602x layout the wireless map documents.
2. **PERST# is a GPIO write, not PMU/SPMI — but confirm the GPIO provider.**
   Op "PERST# deassert" drives GPIO 4. GPIO writes through the ordinary
   `apple,gpio` controller are allowed; **the safety gate is whether GPIO 4
   resolves through `smc-pmu`** (as the trackpad `gp1c` reset did — forbidden) or
   a plain gpio bank. **Action before any live run: resolve GPIO 4's provider in
   the ADT; if it is smc-pmu-backed, PERST# deassert is forbidden and port-0
   bring-up is blocked the same way the trackpad reset was.** (GPIO 0 fn2 CLKREQ#
   is pinmux, lower risk.)
3. **Massive MSIMAP-clear loop (512 writes)** is benign zeroing of the MSI vector
   map, matching the t602x/t6031 driver; no new addresses.
4. **Stop points for the eventual live ladder (one boundary at a time):**
   - Sub-step A: ops 352–(pre-PERST) — port init + tunables + RID2SID/MSIMAP +
     link config, **stop before `PERST# deassert`**. Confirms the port
     programming applies with no SError/DART fault.
   - Sub-step B: add `PERST# deassert` + the LNKCAP/speed/width ops + a **link-up
     poll** (LTSSM/LNKSTS), stop before touching the endpoint's config space.
     Pass = link-up (L0) with the BCM4388 present in config space reads.
   - Endpoint enumeration / DART stream setup / firmware load are later stages.

## Dependencies / status

Gated on 068 (op-115) → full PHY (115–351) → this port-0 stage. The port-1
(GL9755 SD reader, ops 962–1571, PERST# GPIO 5) subset is structurally identical
and can reuse this review. Deliverable: this pre-review + stop-point ladder;
**one open item to close before a live proposal — GPIO 4 provider check (finding
2).** No rig, no MMIO performed. Ticket 044 done (pre-review); the GPIO-4 ADT
check is folded into the eventual link-up rig proposal.
