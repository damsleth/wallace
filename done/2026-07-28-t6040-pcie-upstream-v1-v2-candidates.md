# PCIe candidates V1/V2 on upstream's t6040 path — built, hashed, awaiting review + attended run

Supersedes the approach of patching our diverged fork (ticket 175). Both variants are built
reproducibly and **not run**. Booting either performs the full PCIe PHY + port sequence — upstream
has no diagnostic early return — so both are **attended-only**.

## Why this replaces the earlier candidate

Today's kernelcache decode produced delta **D2** (the PHY release must clear **BIT(4)**, not
t602x's BIT(7)). That correction is **already merged upstream** (PR 633): `apcie,t6040` matches
`regs_t8132` with `.phy_ctrl_reset = APCIE_PHY_CTRL_RESET_T8132 = BIT(4)`. Verified directly in
`upstream/main:src/pcie.c`. Our fork had been clearing BIT(7) on t6040 through **every** op-115 run.

So rather than add D2 to our fork (commit `19edc72b`, retained only as the decode record), the
candidate is now **upstream's PCIe path**, which is the shape reported to work on M4 hardware and
carries no scaffolding.

## The two variants, and the hypothesis each tests

Branch `wallace/t6040-pcie-upstream` in `~/Code/m1n1` (worktree-built; the branch is in the main repo).

### V1 — upstream PCIe, nothing added
- Commit `04e8829c` — merge of `upstream/main` into our t6040 line, taking `src/pcie.c` **wholesale
  from upstream** (drops our trace routing, staged early returns, and local `regs_t6040`), while
  keeping our own fixes the merge preserves — notably the **stage-2 log-buffer guard at top of RAM**
  (`eed11760`), which fixed a real M4 SError and which upstream lacks.
- Also inherits from upstream: the **GXF guarded-stack fix** (`2ea75b66` — our earlier GXF/GENTER
  experiments predate it) and the **ATC `LN0/LN1_RX_TOP_USB_EQA`** offsets (`639e0506`).
- Binary: `linux-build-out/m1n1-t6040-pcie-V1-upstream-04e8829c.bin`
  SHA-256 `28a4e0cf812d48ab40337be9578381d66c61b5ac91730bb0b950930f77a93299`,
  tag `t6040-pcie-upstream-04e8829cbc47`, **two byte-identical clean builds**.
- **Hypothesis:** the wrong PHY reset bit was the *entire* cause of the `reg[3]+0x90` hang, and our
  ticket-058 clkgen PLL work was never a precondition. Upstream reaching link-up on plain M4 with no
  clkgen handling at all is the evidence for this.

### V2 — V1 plus the T6040 clock-source sequence
- Commit `7ae7fbdf` adds, **gated on `apcie,t6040` only** (t8132 and all other SoCs keep upstream
  behaviour byte-for-byte): the `apcie-cio3pllcore-tunables` (reg[5]) and `apcie-pcieclkgen-tunables`
  (reg[6]) application, the live-proven ticket-058 clkgen PLL enable + lock poll, and **delta D1**
  (`clkgen[0] |= BIT(5)`), placed between axi2af and the common tunables to match Apple's decoded
  order. All addresses ADT-derived; no new constants beyond the bit numbers.
- Binary: `linux-build-out/m1n1-t6040-pcie-V2-up-d1-7ae7fbdf.bin`
  SHA-256 `3916bf1581d18862a1585f4346aabc155302f786ae0656c641cf4ef2292445fe`,
  tag `t6040-pcie-up-d1-7ae7fbdf44f8`, **two byte-identical clean builds**.
- **Hypothesis:** T6040 (M4 Pro, more CIO/PCIe blocks than plain M4) additionally needs the clock
  sources programmed and clkgen bit 5 set before the PHY-IP aperture responds.

**Run V1 first.** It is the smaller change and a negative result immediately promotes V2. Escalating
the other way round would leave us unable to attribute a success.

## Run plan (attended)

Same harness as ticket 068 — but note the **observability problem that wasted today's R3 run**:
this must be run where the transcript is actually captured. m1n1's own boot log *is* relayed over the
gadget proxy (it reaches `run_actions()`/`usb_init()`), so unlike the R3 experiment this candidate
**is** observable over a caught dual-mode window. Running it over KIS with the rollback loader
enrolled is still preferable, and is required anyway for the HPM work.

1. Fresh proxy; chainload V1 with the PCIe kernel DT (`t6040-j614s-dcuart-pcie`).
2. Expected new lines: `pcie: Initializing t6040 PCIe controller`, then the PHY sequence.
3. **PASS** = it gets past the first PHY-IP access (previously the hang point) and reports port/link
   status. Then: BCM4388 firmware (ticket 168) and WiFi becomes reachable.
4. **FAIL (hang at the PHY-IP access)** = boot V2 in the same session and compare.
5. Either way record the transcript in `done/` and update tickets 124/175.

Recovery is the sanctioned DebugUSB reboot — the observed failure mode for this path has always been
a hang, never an SError.

## Caveats, stated plainly

- Upstream's t8132 path was presumably validated on **plain M4 (t8132, J773g Mac mini)**, not on
  **M4 Pro (t6040)**. The `apcie,t6040` match exists upstream but I have no evidence anyone ran it on
  an M4 Pro. That is precisely what V1 tests.
- I have **not** verified that yuka reached PCIe link-up on M4; the merged PR and the explicit
  `apcie,t6040` compatible are the evidence, and that is inference, not a reported result.
- Upstream enables **all** clock gates at once (`pmgr_adt_power_enable`) whereas Apple defers gate 7
  (`APCIE_PHY_SW`). Our own 2026-07-14 staged run proved early gate-7 enable was **not** the cause of
  the failure, so this delta is knowingly left alone to keep V1 identical to upstream.
- `regs_t8132` sets `fuse_idx = 5`, which our decode calls the CIO PLL-core window. It is harmless
  because `fuse_bits = NULL` (the base is read, never used), but do not build anything on upstream's
  naming there.
- Neither variant has had the cross-agent exact-artifact review (COORDINATION.md). That review is a
  gate before either boots.
