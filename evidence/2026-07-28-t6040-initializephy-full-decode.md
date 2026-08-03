# T6040 ticket 124 — `ApplePCIEBaseT8132::_initializePhy()` fully decoded (2026-07-28)

Offline static analysis of the paired 25F84 kernelcache
(`/private/tmp/t6040-kernelcache-25F84.raw`). No hardware touched, no repo files modified
other than this report.

## Summary verdict: YES — the full missing-precondition op list is now extracted

The complete `_initializePhy()` op list, the surrounding `_enableRootComplex()` sequence, and
the authoritative call order are decoded with exact registers, masks, and values. Every
hardware op below is grounded in disassembly (VAs cited); nothing is inferred from symbol
proximity. Three findings matter most for m1n1:

1. **The 2026-07-26 note's headline was wrong.** `_initializePhy`'s first op is a bit-0 RMW on
   **PhyPhy[0]** (shared-PHY `+0x8000`, CPU-phys `0x417008000`), *not* PhyCommon[0]. That was
   the predicted `+0x50`-ish `bl`-attribution skew. m1n1 **already performs this op** (its
   CLK0REQ set). The real deltas are elsewhere.
2. **The "op-115 PLL-lock poll" is not a poll.** `AppleEmbeddedPCIE::_applyTunablesFromData`
   has no poll semantics at all — every tunable entry is a plain RMW
   (`v = read(off); if ((v & mask) != (value & mask)) write(off, (v & ~mask) | (value & mask))`).
   The ADT `apcie-phy-ip-pll-tunables` first entry (off `0x90`, mask `0x1`, value `0x1`) is an
   RMW **setting bit 0 of PhyIP[0x90]** (`0x417040090`). Op-115 in our trace was the *read half
   of that RMW*. The hang is therefore a dead/unclocked PhyIP aperture, not a failed lock wait.
3. **Concrete m1n1 deltas found before the first PhyIP access** (candidate hang causes):
   clkgen[0] bit 5 never set after PLL lock; PhyPhy[0] "reset release" clears the wrong bit
   (m1n1 clears bit 7, Apple clears bit 4); CommonReg[4] gets 0 instead of the ADT `lane-cfg`
   value; plus ordering/delay differences. Full delta table below.

---

## 1. `_initializePhy()` — complete op list, in order

Function: `__ZN18ApplePCIEBaseT813214_initializePhyEv` @ `0xfffffe0009b36c74`, len `0xbbc`,
single exit `retab` @ `0xfffffe0009b3782c`. All accessor calls resolved as **exact** symbol
matches (skew-free; `bl` targets equal the `nm` function starts).

Apertures (CPU-physical, from the live ADT + the `+0x200000000` arm-io ranges delta,
cross-checked 2026-07-27):

| aperture | how addressed | base |
|---|---|---|
| PhyCommon[N] | `_read/_writePhyReg(N + 0x4000)` on shared PHY reg[2] | `0x417004000` |
| PhyPhy[N] | `_read/_writePhyReg(N + 0x8000)` on shared PHY reg[2] | `0x417008000` |
| PhyIP[N] | `ml_io_read32/write32(_phyIPRegistersBaseAddress + N)`, mapped from reg[3] | `0x417040000` |

Ops (register numbers are the accessor argument, i.e. byte offsets within the sub-window):

| # | op | evidence VA |
|---|---|---|
| 1 | `v = read PhyPhy[0]; v \|= 0x1; write PhyPhy[0] = v` (RMW set bit 0) | `0xb36cd4`/`0xb36cec`/`0xb36cf8` |
| 2 | **Poll**: `read PhyPhy[0]` until **bit 2 set** — Apple log: "Waiting for **sleep_b_sml_out**". Unbounded loop, no timeout. | `0xb36e84`–`0xb36e9c` |
| 3 | `IODelay(1)` — 1 µs | `0xb37028` |
| 4 | `write PhyPhy[0] = (last polled value) \| 0x2` (set bit 1, bit 0 stays set) | `0xb37038`/`0xb37048` |
| 5 | **Poll**: `read PhyPhy[0]` until **bit 3 set** — "Waiting for **sleep_b_big_out**". Unbounded. | `0xb371d4`–`0xb371ec` |
| 6 | `write PhyPhy[0] = (last polled value) & ~0x10` (**clear bit 4**) | `0xb37380`/`0xb37390` |
| 7 | `IODelay(1)` | `0xb37394` |
| 8 | `v = read PhyPhy[4]; v \|= 0x1; write PhyPhy[4] = v` (RMW set bit 0) | `0xb373a0`–`0xb373cc` |
| 9 | virtual `_applyTunablesFromData([this+688], &_readPhyIPReg, &_writePhyIPReg, "PHY IP PLL")` — applies ADT **`apcie-phy-ip-pll-tunables`** as RMWs on the PhyIP window (`0x417040000` + entry offset). **This is the first PhyIP access**; its first entry is off `0x90`/mask `0x1`/value `0x1` (op-115's read). | `0xb3742c` (vtable slot `+0xb38`) |
| 10 | virtual `_applyTunablesFromData([this+696], &_readPhyIPReg, &_writePhyIPReg, "PHY IP AUSPMA")` — ADT **`apcie-phy-ip-auspma-tunables`**, same mechanism | `0xb3748c` |
| 11 | `v = read PhyIP[0x90]; v &= ~0x10000; write PhyIP[0x90] = v` (**clear bit 16**) | `0xb37494`–`0xb374c0` |
| 12 | `v = read PhyPhy[4]; v \|= 0x10; write PhyPhy[4] = v` (RMW set bit 4) | `0xb374cc`–`0xb374f0` |
| 13 | **Poll**: `read PhyPhy[8]` until **bit 0 set** — "Waiting for **max_pclk_good**". Unbounded. | `0xb3767c`–`0xb37694` |
| — | return | `0xb3782c` |

Notes:
- Every `mach_continuous_time`/`kprintf`/`IOLog`/`os_log` block in the function is
  debug-elapsed-time logging gated on global debug flags — no hardware effect, and the polls
  have **no timeout and no failure path**.
- The two PAC-signed constants built at function entry (`0xfffffe0009b35370`,
  `0xfffffe0009b355e0`) are pointer-to-member-function payloads for `_readPhyIPReg`/
  `_writePhyIPReg`, passed as the tunable applier's read/write callbacks (x2..x5).
- vtable slot `+0xb38` of `__ZTV18ApplePCIEBaseT8132` (@ `0xfffffe0008249748`) decodes to
  `0xfffffe00091ee1f8` = `AppleEmbeddedPCIE::_applyTunablesFromData` — verified by reading the
  fixup-chained slot qword, not by name-guessing.
- `[this+688]`/`[this+696]` are `OSData*` fetched in `start()`
  (`0xfffffe0009b31d30`/`0xfffffe0009b31db4`) from ADT properties
  `apcie-phy-ip-pll-tunables` / `apcie-phy-ip-auspma-tunables` (strings at
  `0xfffffe00076ae4c5`/`0xfffffe00076ae4df`).

### Tunable entry format (spdsTunable, from `_applyTunablesFromData` @ `0xfffffe00091ee1f8`)

24-byte stride (`add x8, x8, #24` @ `0xfffffe00091eeb64`): `{u32 offset @0; u32 size @4;
u64 mask @8; u64 value @16}`; `REQUIRE(size == 4)` (panic string @ `0xfffffe00074211d4`).
Apply: read via PMF, **skip the write if `(v & mask) == (value & mask)`** (@ `0xb91ee82c`),
else `v = (v & ~mask) | (value & mask)`, write. The only backward branch in the function is
the entry loop — **no poll entries exist**.

## 2. PortPhyGlue: NOT touched

`ApplePCIEBaseT8132` (root-complex level) has **no PortPhyGlue data accessor at all** — only
the index accessor `dtRegMapPortPhyGlueIndex(uint)` (vtable slot `+0xbc8`), which is consumed
by the per-port class `ApplePCIEBaseT8132Port` during later port bring-up. Neither
`configure()`, `_enableRootComplex()`, `_configPciePLLs()`, `_enableClocks()` nor
`_initializePhy()` reads or writes the glue window (`0x417020000 + port*0x4000`). **Nothing
before the first PHY-IP access touches PortPhyGlue.**

## 3. Authoritative call order

Established by disassembling `AppleEmbeddedPCIE::configure` (`0xfffffe00091ecabc`, the base
class of T8132 — its vtable is at `__ZTV17AppleEmbeddedPCIE`) and
`ApplePCIEBaseT8132::_enableRootComplex(bool)` (`0xfffffe0009b35fe0`).

**Boot path**: `ApplePCIEBaseT8132::configure()` (@`0xfffffe0009b31e40`) only *maps* the five
extra apertures — `_phyRegisters` = `dtRegMapPhyIndex(0)` (reg[2]), `_phyIPRegisters` =
`dtRegMapPhyIndex(1)` (reg[3]; `w1=1` @ `0xb3216c`, stored to `this+568/576/584`), axi2af,
cio3pllcore, pcieclkgen — then the base `AppleEmbeddedPCIE::configure` runs:

1. ... range/port setup ...
2. virtual slot `+0xad8` = `_enableClocks()` (@ `0x91ed10c`)
3. virtual slot `+0xaf0` = **`_enableRootComplex(false)`** (@ `0x91ed134`, `w1=0` explicit)
4. per-port `AppleEmbeddedPCIEPort::autoEnable()` → `_waitForLinkUp` (ports only after RC).

The **wake path** (`callPlatformFunction` @ `0x91f0508`, and `_updatePortReport`) calls
`_enableRootComplex(true)` (`w1=1` @ `0x91f0514`).

**`_enableRootComplex(b)` internal order** (T8132 override, the master sequencer):

| step | only if `b` | op |
|---|---|---|
| E1 | yes | `AppleARMIODevice::enableDeviceClock(1, i)` for i = 0 .. `_totalClks`−2 (provider nub at `this+560` = `safeMetaCast(provider, AppleARMIODevice)`; vtable slot `+0x8a8` of `__ZTV16AppleARMIODevice` = `enableDeviceClock(uint,uint)` @ `0xfffffe0008a9fc34`) |
| E2 | yes | `_applyTunablesFromData([this+664] = apcie-axi2af-tunables, axi2af accessors, "APCIe AXI2AF")` |
| E3 | yes | `_applyTunablesFromData([this+672] = apcie-cio3pllcore-tunables, cio3pllcore accessors, "CIO3PLL Core")` |
| E4 | yes | if `getPortCount() != 0`: **`_configPciePLLs()`** (see below) |
| E5 | yes | `v = read clkgen[0]; v = (v & ~0x20) \| 0x20; write clkgen[0] = v` — **set bit 5** (@ `0xb36224`–`0xb36254`) |
| E6 | yes | `enableDeviceClock(1, _totalClks−1)` — the **last** clock gate, only now |
| E7 | always | `_applyTunablesFromData([this+496], CommonReg accessors, "APCIe common")` — the apcie-common tunables, on reg[1] (`0x414000000`) |
| E8 | always | `_writeCommonReg(0x4, [this+420])` — **CommonReg[4] = ADT `lane-cfg` value** (`this+420` set by `_setLaneCfg` @ `0xfffffe00091ef9e8` from `copyDTProperty("lane-cfg", 4 bytes)` in `start()` @ `0xb31b20`) |
| E9 | always | `_applyTunablesFromData([this+528], PhyReg accessors, "PCIe PHY")` — the apcie-phy tunables, raw offsets into shared-PHY reg[2] |
| E10 | always | **Poll**: `read PhyCommon[0]` until **bit 31 set** — "Waiting for **refpll_clk_good**" (@ `0xb36514`–`0xb3652c`). Unbounded. |
| E11 | always | **`_initializePhy()`** (@ `0xb366bc`) — ops 1–13 above, including the first PhyIP access (PLL tunables) at step 9 |
| E12 | always | `v = read PhyCommon[0]; v = (v & ~0x1) \| 0x1; write PhyCommon[0] = v` — set bit 0 (@ `0xb366cc`–`0xb36704`) |
| E13 | always | `v = read PhyPhy[0]; v \|= 0x8000000; write PhyPhy[0] = v` — **set bit 27** (@ `0xb36710`–`0xb36734`) |
| E14 | always | `_writeCommonReg(0x54, 0x140)` (blind write; vtable slot `+0xb20` = `AppleEmbeddedPCIE::_writeCommonReg`, `w1=0x54 w2=0x140` @ `0xb36760`–`0xb3676c`) |
| E15 | always | `_enableGTBToPTM(1)` (@ `0xb367a0`, slot `+0xb50` → `0xfffffe0009b380d4`): `v = readCommonReg(0x50); v \|= 0x1; writeCommonReg(0x50, v)` |
| E16 | always | **Poll**: `readCommonReg(0x58)` until **bit 0 set** — "Waiting for **gtb_initialized**" (@ `0xb3692c`–`0xb36968`). Unbounded. |

**`_configPciePLLs()`** (@ `0xfffffe0009b35e98`, complete):

1. `_applyTunablesFromData([this+680] = apcie-pcieclkgen-tunables, clkgen accessors, "PCIECLKGEN")`
2. `v = read clkgen[4]; v = (v & 0x7fffffff) | 0x80000000; write clkgen[4] = v` — set bit 31
3. `v = read clkgen[0]; v &= ~0x4; v &= ~0x2; v |= 0x1; write clkgen[0] = v` — clear bits 2,1; set bit 0
4. **Poll**: `read clkgen[0]` until **bit 31 clear**. Unbounded.

(clkgen = reg[6], CPU-phys `0x415044000`; cio3pllcore = reg[5], `0x415046200`.)

So the tunable ordering is: axi2af → cio3pllcore → pcieclkgen (inside `_configPciePLLs`) →
apcie-common → lane-cfg write → apcie-phy → refpll poll → `_initializePhy` (phy-ip-pll →
phy-ip-auspma inside it). The `apcie-phy-ip-pll-tunables` "poll spec" is applied as a plain
RMW at E11/step 9 — **there is no PLL-lock poll on PhyIP[0x90] anywhere in the driver**; the
only post-tunable PhyIP op is the bit-16 clear (step 11), and the "lock waits" are the PhyPhy
polls (`sleep_b_*`, `max_pclk_good`) and PhyCommon `refpll_clk_good`.

## 4. m1n1 delta table (vs `~/Code/m1n1/src/pcie.c` `pcie_init_controller`, `regs_t6040` branch)

m1n1 t6040 facts checked in source: `num_phys = 1` (line 297, never overridden), `fuse_bits =
NULL` (no fuse ops — matches Apple, which has none), `phy_base[0] = reg[2]+0x8000` and
`phy_common_base = reg[2]+0x4000` (compat==T8122 block, line ~412) — both match Apple's
accessor addends exactly.

### Ops m1n1 ALREADY performs correctly (Apple-equivalent)

| Apple op | m1n1 |
|---|---|
| E1/E6 clock gates 0..6 then 7 last | `pmgr_adt_power_enable_index` 0..6, gate 7 after PLL ✓ |
| E2 axi2af tunables | `pcie_apply_local(apcie-axi2af-tunables, axi_idx=4)` ✓ |
| E3 cio3pllcore tunables | `pcie_apply_local(..., idx 5)` ✓ |
| PLLs-1 clkgen tunables | `pcie_apply_local(apcie-pcieclkgen-tunables, idx 6)` ✓ |
| PLLs-2 clkgen[4] bit31 | `set32(clkgen+0x4, 0x80000000)` ✓ |
| PLLs-3 clkgen[0] bits2,1←0, bit0←1 | `mask32(clkgen+0x0, 0x7, 0x1)` ✓ (same net effect) |
| PLLs-4 poll clkgen[0] bit31→0 | `poll32(clkgen+0, 0x80000000, 0, 250000)` ✓ |
| E7 common tunables | `pcie_apply_local(apcie-common-tunables, rc_idx=1)` ✓ (but ordered before cio3pll/clkgen — Apple does it after; see deltas) |
| E9 phy tunables | `pcie_apply_local(apcie-phy-tunables, phy_idx=2)` ✓ |
| E10 poll PhyCommon[0] bit31 (refpll_clk_good) | `poll32(phy_common_base+0, BIT(31), BIT(31))` ✓ |
| init-1/2 PhyPhy[0] bit0 + poll bit2 | `set32(phy+0, CLK0REQ)` + poll CLK0ACK ✓ |
| init-4/5 PhyPhy[0] bit1 + poll bit3 | `set32(phy+0, CLK1REQ)` + poll CLK1ACK ✓ |
| init-8 PhyPhy[4] \|= 1 | `set32(phy_base+4, 0x01)` (compat==T8122 branch fires for t6040) ✓ |
| init-9/10 phy-ip pll + auspma tunables | `pcie_apply_local_addr(...)` — code exists but the t6040 branch currently **returns −1 after a read-only diagnostic of the first PLL entry** (the op-115 probe) |
| init-12 PhyPhy[4] \|= 0x10 | `set32(phy_base+4, 0x10)` ✓ (after tunables — correct position) |
| init-13 poll PhyPhy[8] bit0 (max_pclk_good) | `poll32(phy_base[0]+off+0x8, 1, 1)` ✓ — `off=0` since num_phys==1; note Apple polls this *before* E12/E13, m1n1 after its PHYCMN mask; see deltas |
| E12 PhyCommon[0] bit0 | `mask32(phy_common_base+0, GENMASK(1,0), 1)` ≈ ✓ (also clears bit 1 — Apple preserves it; net risk low but not identical) |
| E14 CommonReg[0x54] = 0x140 | `write32(rc_base+0x54, 0x140)` ✓ |
| E15 CommonReg[0x50] bit0 | `write32(rc_base+0x50, 0x1)` — blind write vs Apple's RMW; equivalent iff other bits are 0 |
| E16 poll CommonReg[0x58] bit0 | `poll32(rc_base+0x58, 1, 1)` ✓ |

### Ops m1n1 does NOT perform, or performs differently — the patch-relevant list

| # | delta | Apple evidence | severity for the op-115 hang |
|---|---|---|---|
| D1 | **clkgen[0] \|= 0x20 (set bit 5) after PLL lock, before the last clock gate** — E5. m1n1 goes straight from the PLL-lock poll to enabling gate 7. | `0xfffffe0009b36224`–`0xb36254` | **High** — happens strictly before any PhyIP access; a plausible PhyIP clock enable |
| D2 | **PhyPhy[0] bit-4 clear** (init-6, after sleep_b_big_out, before PhyPhy[4]\|=1). m1n1 instead clears **bit 7** (`APCIE_PHY_CTRL_RESET`, a t602x constant). On T8132 Apple never touches bit 7 here; it clears bit 4 (and reads back the polled value, i.e. bits 0,1 stay set). | `0xfffffe0009b37380` (`and w8, w8, #0xffffffef`) | **High** — wrong bit before first PhyIP access |
| D3 | **CommonReg[4] = ADT `lane-cfg`** (E8). m1n1 writes `rc_base+0x4 = 0` (the "???" write). If J614s's `lane-cfg` ≠ 0, m1n1 programs the wrong lane config before the PHY comes up. *Action: read `lane-cfg` from `/arm-io/apcie0` and write that value.* | `0xb36324` (slot `+0xb20`, `w1=4`, `w2=[this+420]`) | Medium |
| D4 | **Ordering**: Apple applies apcie-common tunables (and lane-cfg) *after* cio3pll/clkgen PLL and the last clock gate; m1n1 applies common tunables before them. | E-table above | Low–medium |
| D5 | **IODelay(1 µs) between the sleep_b_sml_out ack and the CLK1 request** (init-3), and another after the bit-4 clear (init-7). m1n1 has only the post-"reset" udelay. | `0xb37028`, `0xb37394` | Low |
| D6 | **PhyIP[0x90] &= ~0x10000 (clear bit 16)** after the AUSPMA tunables, before PhyPhy[4]\|=0x10 (init-11). m1n1 has no equivalent anywhere. | `0xb37494`–`0xb374c0` | N/A for the hang (after first PhyIP access) but **required for a complete sequence** |
| D7 | **PhyPhy[0] \|= bit 27 (0x8000000)** post-init (E13). m1n1's t8122-derived tail does `set32(phy+0, 0x200)` (bit 9) instead — a T8122 value, wrong for T8132. | `0xb36710`–`0xb36734` | N/A for hang; wrong for completion |
| D8 | **max_pclk_good poll position**: Apple polls PhyPhy[8] bit0 at the *end of `_initializePhy`*, i.e. before E12/E13; m1n1 polls it after its PHYCMN mask write. Also m1n1's `+off` quirk ("why always PHY 1") is inert here only because num_phys==1. | `0xb3767c` | Low |
| D9 | Apple polls are unbounded; m1n1 uses timeouts. Fine to keep timeouts, but if `max_pclk_good`/`gtb_initialized` time out after fixing D1–D7, the earlier steps are wrong — Apple's driver would simply hang there too. | — | informational |

**Bounded patch recipe** (in m1n1 t6040 branch order): (a) after the clkgen PLL-lock poll,
add `set32(clkgen_base + 0x0, 0x20)` before enabling gate 7 [D1]; (b) in the PHY loop replace
`clear32(phy, BIT(7))` with `clear32(phy, BIT(4))` for t6040, with a `udelay(1)` before the
CLK1 request [D2, D5]; (c) write the ADT `lane-cfg` value (not 0) to `rc_base + 0x4`, after
the clkgen/gate-7 block to match Apple's order [D3, D4]; (d) after applying the AUSPMA
tunables and before `set32(phy+4, 0x10)`, add `clear32(phy_ip_base + 0x90, BIT(16))` [D6];
(e) in the tail replace `set32(phy+0, 0x200)` with `set32(phy+0, BIT(27))` for t6040 and move
the `max_pclk_good` poll before the PHYCMN mask [D7, D8]; (f) remove the two read-only
diagnostics (`return -1`) once the above is in. All addresses stay ADT-derived (reg[2]+0x4000,
reg[2]+0x8000, reg[3], reg[6]) — no new constants beyond the bit numbers.

## Method / evidence

- Kernelcache: `/private/tmp/t6040-kernelcache-25F84.raw` (119 MiB, extracted 07-24).
  Segment map from `llvm-otool -l`; VA→file-offset by script over all 8 segments
  (`__TEXT_EXEC` vmaddr `0xfffffe0008954000` fileoff 26542080; `__PRELINK_TEXT` vmaddr
  `0xfffffe000700c000` fileoff 32768 — used to read the format/property strings;
  `__DATA_CONST` vmaddr `0xfffffe0007d30000` fileoff 13811712 — used to decode vtable slots).
- Disassembler: scratchpad `dis.py` — extracts bytes at the symbol's exact `nm` VA, feeds
  `llvm-mc --disassemble --triple=aarch64`, annotates per-instruction VAs, resolves `bl`
  targets against the full symbol table (exact-match required; near-matches flagged INEXACT),
  and resolves `adrp+add` string refs by reading the target bytes from the file. One bug fixed
  during the session: `llvm-mc` prints `adrp` immediates **already scaled to bytes** — the
  earlier ×4096 rescale produced garbage string addresses; all string annotations in this
  report are from the fixed script and were verified to decode as printable C strings.
- Vtable slot resolution: read the fixup-chained qword at `ZTV + 0x10 + slot`, target =
  `0xfffffe0007004000 + (qword & 0xffffffff)`; validated by round-tripping known slots
  (e.g. `+0xb28`→`_readPhyReg`, `+0xb30`→`_writePhyReg`, matching the accessor thunks'
  `add w1, w8, #4/#8, lsl #12` addend code at `0xb3586c`/`0xb35924`).
- Accessor addend proof: `_readPhyCommonReg` @ `0xb3584c` does `add w1, w8, #4, lsl #12`
  (+0x4000) then slot `+0xb28`; `_readPhyPhyReg` @ `0xb35904` does `add w1, w8, #8, lsl #12`
  (+0x8000); write variants use slot `+0xb30`. `_readPhyIPReg` @ `0xb35370` panics if
  `[this+576]` (`_phyIPRegistersBaseAddress`) is null, else `ml_io_read32([this+576] + reg)`;
  the debug path prints `[this+584] + reg` (`..BaseAddressPhys`).
- `enableDeviceClock` identification: `movz x17,#0x8a8` slot on the object from
  `safeMetaCast(provider, AppleARMIODevice::metaClass)` (metaclass pointer at
  `0xfffffe0008249690` decoded to `__ZN16AppleARMIODevice9metaClassE`);
  `__ZTV16AppleARMIODevice` slot `+0x8a8` = `AppleARMIODevice::enableDeviceClock(uint,uint)`.
- `_enableRootComplex` caller scan: byte-pattern search for `movz x17,#0xaf0`
  (`11 5e 81 d2`) across `__TEXT_EXEC`, filtered to PCIe classes → 3 relevant sites
  (`AppleEmbeddedPCIE::configure`+0x668 `w1=0`; `callPlatformFunction`+0x90 `w1=1`;
  `_updatePortReport`+0x278).

Key raw excerpts (from the annotated disassembly, VAs abbreviated to low 32 bits):

```asm
; _initializePhy first op — PhyPhy[0] |= 1 (NOT PhyCommon)
9b36cbc  mov  w1, #0
9b36cd4  bl   -> _readPhyPhyRegEj          ; exact match
9b36cec  orr  w8, w8, #0x1
9b36cf8  bl   -> _writePhyPhyRegEjj

; sleep_b_sml_out poll (bit 2)
9b36e84  ldr x0,[sp,#112]; mov w1,#0
9b36e8c  bl   -> _readPhyPhyRegEj
9b36e9c  tbz  w8, #2, -24                   ; loop while bit2 == 0

; PhyIP[0x90] bit-16 clear
9b37494  mov  w1, #144                      ; 0x90
9b3749c  bl   -> _readPhyIPRegEj
9b374b4  and  w8, w8, #0xfffeffff           ; clear bit 16
9b374c0  bl   -> _writePhyIPRegEjj

; enableRootComplex: clkgen[0] |= 0x20 after _configPciePLLs (m1n1 delta D1)
9b36210  bl   -> _configPciePLLsEv
9b36224  bl   -> _readPcieclkgenRegEj       ; w1=0
9b3623c  and  w8, w8, #0xffffffdf
9b36248  orr  w8, w8, #0x20
9b36254  bl   -> _writePcieclkgenRegEjj

; enableRootComplex tail: PhyPhy[0] |= bit27 (m1n1 delta D7)
9b36710  bl   -> _readPhyPhyRegEj           ; w1=0
9b36728  orr  w8, w8, #0x8000000
9b36734  bl   -> _writePhyPhyRegEjj

; CommonReg[0x54] = 0x140 then _enableGTBToPTM(1)
9b36760  mov  w1, #84 ; 0x54
9b36764  mov  w2, #320 ; 0x140
9b3676c  blraa ...                          ; slot +0xb20 = _writeCommonReg
9b367a0  blraa ...                          ; slot +0xb50 = _enableGTBToPTM
```

## Explicitly NOT resolved / follow-ups

- **J614s `lane-cfg` value** (for D3): not readable statically from the kernelcache — read
  `/arm-io/apcie0` `lane-cfg` over the proxy in the next attended/read-only ADT session. If it
  is 0, D3 collapses to a no-op and m1n1's existing `rc_base+0x4 = 0` write is already right.
- **`_regIndex` byte values** (`this+709/710/711` etc.): the constructor initializes them to
  0xff and `start()` fills them via `copyDTProperty`-driven parsing I did not fully trace. The
  effective values (phy=reg[2], phyIP=reg[3], cio3pll=reg[5], clkgen=reg[6]) are instead
  confirmed by the live tunables trace addresses (`0x417000000`/`0x417040090`) and the
  configure() map order — consistent, but the parser itself is undecoded.
- **Semantics of clkgen[0] bit 5 and PhyPhy[0] bits 4/27**: names unknown (no strings). Bit
  assignments are exact; meanings are inferred only from position in the sequence.
- **`enableDeviceClock` index→ADT mapping**: assumed to be the apcie node's clock-gate list in
  ADT order, matching m1n1's `pmgr_adt_power_enable_index` usage — consistent with the boot
  logs to date but not re-verified here.
- The `b=false` boot path means macOS at cold boot *skips* E1–E6 (clocks/PLLs), relying on
  iBoot state. m1n1 replaces iBoot here, so it must keep performing E1–E6 (as it does), and
  Apple's wake path shows the full canonical ordering used above.
