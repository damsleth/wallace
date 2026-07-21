# T6040 PCIe op-115 route-finding — the PHY-IP aperture precondition (2026-07-21)

Ticket 058 (offline, P1, pcie track). Continues
`done/2026-07-14-t6040-pcie-op115-static-analysis.md` and the read-only
isolation result (`done/2026-07-14-t6040-pcie-op115-read-result.md`): the first
PHY-IP access hangs on its **read** side, so a precondition that makes the
`reg[3]` PHY-IP aperture (phys `0x417040000`) respond to reads is not satisfied
at m1n1's op-115 point. This ticket finds what that precondition is. Static
only; no rig, no MMIO. A changed live sequence still needs a fresh manifest,
cross-review, and CJ approval.

## m1n1 side — exactly what state the controller is in at the hang (verified)

From `~/Code/m1n1/src/pcie.c` (branch `main`), `regs_t6040`:

```
.type = APCIE_T6031, .compat = APCIE_T8122, .shared_reg_count = 7,
config_idx=0  rc_idx=1  phy_common_idx=2  phy_idx=2  phy_ip_idx=3  axi_idx=4
PHY_STRIDE=0x4000  PHYIP_STRIDE=0x40000
```

So t6040 is driven by the T8122/T6031 template. Register apertures (ADT
`reg[]`, `/arm-io` bus base `0x3_00000000`): `phy`/`phy_common` = `reg[2]`
(`0x417008000`), **`phy_ip` = `reg[3]` (`0x417040000`)**, `axi` = `reg[4]`.

The PHY bring-up preceding op-115, in order, and **which aperture each touches**:

| # | m1n1 action | aperture | notes |
|---|---|---|---|
| — | AXI / common / CIO3-PLL / PCIe-clkgen tunables | reg[4], reg[1], reg[5], reg[6] | ops ≤70, proven |
| — | enable T6040 PHY clock gate `APCIE_T6040_PHY_CLOCK_GATE_IDX` (=7) | pmgr | `pmgr_adt_power_enable_index` |
| — | `apcie-phy-tunables` (controller PHY) | **reg[2]** | via `phy_idx=2` |
| — | poll `phy_common+0x000` bit31 (100 MHz refclk) | **reg[2]** | `APCIE_PHYCMN_CLK_100MHZ` |
| — | per-phy: set `CLK0REQ`, poll `CLK0ACK`; set `CLK1REQ`, poll `CLK1ACK` | **reg[2]** | `phy_base+0x000`, BIT(0..3) |
| — | clear `RESET` (BIT7) at `phy_base+0x000`; `udelay(1)` | **reg[2]** | reset release |
| 114 | `set32(phy_base+4, 0x01)` | **reg[2]** | the `compat==T8122` "pre-tunable control" |
| — | fuse loop | reg[3] | **SKIPPED — `fuse_bits==NULL` for the t6040/t8122 selector** |
| **115** | read first `apcie-phy-ip-pll-tunables` entry at `phy_ip_base+0x90` | **reg[3]** | **first reg[3] access → HANGS** |

Two facts this pins down:

1. **Every operation before op-115 touches `reg[2]` (or pmgr/other apertures),
   never `reg[3]`.** Because `fuse_bits==NULL` for t6040 (confirmed at
   `src/pcie.c` fuse-selector: `apcie,t6040 → fuse_bits = NULL`), the fuse-loop
   `mask32(phy_ip_base…)` that *would* be the first reg[3] touch on t8103/t600x
   is skipped. So op-115 is unambiguously the **first** `reg[3]` access, and the
   read-side hang means the aperture itself is not live yet — not a mid-sequence
   corruption.
2. m1n1's whole `reg[3]` ungate assumption is inherited from the T8122/T6031
   template: it releases clocks/reset on `reg[2]` and the `+4=0x01` control, and
   expects `reg[3]` to answer. On t6040 that assumption fails.

The leading hypothesis is therefore: **t6040 has a PHY-IP (`reg[3]`) ungate —
a clock-enable, power/reset de-assert, or aperture-enable — that lives outside
the `reg[2]` CLK0/CLK1/RESET/`+4` sequence, and Apple performs it before its
first `_readPhyIPReg`.** The candidate mechanisms to confirm from Apple's driver
are: (a) an extra register write distinct from the reg[2] sequence; (b) a
different value/offset for the `+4` control on t6040; or (c) an additional pmgr
clock-gate index beyond `IDX 7`.

## Apple side — partial, and why it's not yet a grounded precondition

Source binary: `AppleT6040PCIe` extracted from the T6041 `mac16j` kernelcache
(Darwin 24.6.0, `RELEASE_ARM64_T6041`; see the source note). Full C++ symbols
present. Grounded so far:

- `_readPhyIPReg`/`_writePhyIPReg` (0xfffffe000a1c2190 / …2214) load the PHY-IP
  (reg[3]) mapped base from **object field `[this + 0x228]`** and do a
  width-selected `ml_io_read32`/`write32` at base+offset. So field +0x228 is the
  reg[3] aperture; if anything ungates it, it happens before this field is first
  used.
- `_initializePhy` (…2b88) goes **straight into** the "PHY IP PLL"/"PHY IP
  AUSPMA" tunable-apply virtual calls (the repeated `mov w1,0x8000; blraa`); it
  has **no** pre-tunable reg[3] ungate of its own. So any ungate is earlier —
  in `_enableRootComplex` (…257c) or `configure` (…130c).
- `_enableRootComplex` is 1340 bytes and is **almost entirely PAC-authenticated
  virtual dispatch** (`blraa x8,x17` with `movk …,lsl 48`): its register touches
  go through vtable helpers with computed offsets, so the specific apertures
  cannot be read off a flat disassembly without resolving each vtable slot to its
  method body. This is the tedious part a background disasm agent was assigned;
  that agent stalled at launch (no output in 6.5 h) and was retired.

**Cross-check against the only other M4-family attempt (from the IRC review,
`done/2026-07-21-asahi-dev-irc-review.md`):** yuka's
`github.com/yuyuyureka/m1n1/tree/feature/untested-t8142-pcie` drives t8142 (same
M4 cohort as t6040/t6041) with the plain `regs_t8132` template and adds **no**
extra PHY-IP ungate, no extra clock-gate index, and no reg[3] write before the
tunables — and it is explicitly *untested*. So **there is no known-good M4-family
PCIe reference in m1n1**; the reg[3] precondition is unsolved everywhere, not just
here. The Apple kernelcache is the only source of truth, and it's behind virtual
dispatch.

## Hypotheses (narrowed, not yet grounded — do NOT turn into a live write yet)

On t8122/t6031 the identical template works, so reg[3] there is live after the
reg[2] clock/reset sequence plus the PMGR clock-gates. On t6040 it is not. The
live candidates, in order:

1. **An additional PMGR power domain / clock-gate ungates the PHY-IP block.** The
   J614s ADT exposes `APCIE_PHY_SW`, `APCIE_ST0/ST1`, `APCIE_SYS_ST0/ST1`,
   `APCIE_SYS_GP`, `APCIE_GP`. m1n1 enables the apcie node's `clock-gates`
   (incl. the T6040 late gate IDX 7 = `APCIE_PHY_SW`) but may be missing the one
   that gates reg[3] specifically. This is the most likely and the most
   testable.
2. **`set32(phy_base+4, 0x01)` has different semantics/offset on t6040** than the
   t8122 template assumes, so the reg[3] aperture never leaves reset.
3. A ready-bit poll on reg[2]/reg[3] that Apple does and m1n1 doesn't.

## Next step (two grounded options, pick per cost)

- **A — resolve the Apple bring-up (offline, higher cost):** a focused r2 session
  that resolves the vtable slots called in `_enableRootComplex`/`configure` to
  method bodies, enumerating every MMIO aperture + offset touched before the
  first `_readPhyIPReg`, and maps each object-field base to a `dtRegMap*` index
  via `configure`. Output an ordered trace; only then propose a manifest.
- **B — read-only PMGR-domain probe (rig, gated):** after the proven
  stop-before-PHY prefix, enable each candidate PMGR domain
  (`APCIE_SYS_ST0/ST1`, etc.) read-only-style and do a single 32-bit read of
  `0x417040090` after each, stopping on the first that returns instead of
  hanging. Read-only, ADT-derived indices only, one intentional stop — but it
  needs a manifest, cross-review, and approval, and it competes with Sol for the
  rig, so prefer A first.

Do not invent a reg[3] ungate offset or promote any hypothesis to a live write
without grounding it in option A or a reviewed option-B result.

## Source

Paired T6041 target kernelcache `kernelcache.release.mac16j`
(Darwin 24.6.0, `xnu-11417.140.69.710.16`, `RELEASE_ARM64_T6041`),
SHA-256 `d5deb3335ff709bf9b487b975838925bf6a43b06b23bc7e920e61c5f0f0983a1`,
from this host's Preboot `restore-staged`. `AppleT6040PCIe` kext extracted with
`ipsw kernel extract`; symbols intact. No Apple binary committed.
