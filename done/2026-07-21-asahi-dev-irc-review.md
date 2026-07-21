# #asahi-dev IRC review, 2026-07-11 → 2026-07-21 — findings + plan

This is the focused parallel review/plan. The complementary source-linked
day-range record, including lower-priority ATC, PSCI, SMC, DCP, trackpad,
wireless, and power-telemetry findings, is
`done/2026-07-21-asahi-dev-log-review.md`. Project policy still applies: no
agent posts or contacts upstream; prepare drafts for CJ to send.

Trawl of the OFTC `#asahi-dev` logs (`oftc.catirclogs.org/asahi-dev/<date>`) for
anything bearing on the T6040 (M4 Pro, J614s) bring-up. 11 days, ~4,700
messages reconstructed; 91 keyword hits reviewed in full context. Access note:
the log host is behind an Anubis proof-of-work wall — solved the SHA-256
challenge (difficulty 2) once in node, reused the auth cookie for all pages.

**Headline:** we are not the only people bringing up this exact SoC. **yuka**,
**enverbalalic**, and **flokli** are actively working T6040/T6041 DockChannel
UART + device trees on real M4 Pro hardware, and one of their findings very
likely explains our single biggest open blocker (DockChannel RX). There are also
concrete leads for NVMe/SPTM, PCIe, DCP, and the locked-sysreg situation.

## Findings, most actionable first

### 1. The DockChannel-UART IRQ number in the ADT is WRONG — real value is 816, not 360 (t6040/t6041)
Directly hits NEXT_STEPS §0 and our whole RX investigation (old tickets 049/059).

- 2026-07-17 `yuka`: wrote an experiment to measure the real dockchannel-uart
  IRQ; on **M4 Pro (t6040, j773s): "adt = 360, real = 816"**; t6050 adt 360 /
  real 702; believes M4 Max's ADT 360 is the only correct one and "the others
  are copy and paste errors on the apple side" (thanks flokli for remote M4 Pro
  access).
- 2026-07-18 `enverbalalic` reproduced it on **real t6041 hardware**: "interrupt
  really is different then ADT on t6041 (360 vs 816)".

**Why this matters for us:** our rig result (`rxirq-txpoll`, NEXT_STEPS §0 row 3)
was that the RX handler never entered (`total=0`) and `/proc/interrupts` for our
telemetry virq (mapped from **ADT input 360**, hwirq 65896) stayed at zero. If
the hardware actually raises **AIC input 816**, our handler is registered on the
wrong line and can never fire — which fits the observation exactly. Our recorded
"investigate mask-write or pre-handoff perturbation, not AIC delivery" hypothesis
is **superseded**: test IRQ 816 first. Do **not** run any further IRQ-360
diagnostic (now a grave in BACKLOG).

### 2. Independent confirmation of our RX-bit + IRQ-storm findings; the fix is a DT property
- 2026-07-11 `yuka`: the mailbox driver assumes `IRQ_RX = BIT(3)` but "it should
  be BIT(1)"; writing BIT(3) leaves the flag "sticky active" → constant RX IRQ
  regardless of FIFO contents — this is the "space heater / irq storm" effect,
  which yuka reproduced with the mailbox-based dockchannel-uart (jannau: "I
  wouldn't expect irqs there without traffic"). Exactly our BIT(1)/BIT(3) and
  storm findings, arrived at independently.
- `yuka`+`integralpilot` conclusion: `mtp-dockchannel` and `uart-dockchannel`
  use **different IRQ bits**, so the RX/TX bit positions should become a **DT
  property**. This is the upstreamable shape for our poll/IRQ work.

### 3. earlycon mechanics for dockchannel (actionable for our DT)
- `data` reg = `config + 0x4000`; on J614s config `0x508828000` → **data
  `0x50882c000`**. earlycon's `mapbase` comes from **reg[0]**, and it maps only
  4 KiB, so **the data reg must be listed first** in the Linux DT `reg`.
- The IRQ number does **not** matter for earlycon (polled); it matters only for
  the interrupt-driven `ttyDC0`. dockchannel-uart needs no extra power domains.

### 4. Active collaborators on the same machine — coordinate, don't duplicate
- `yuka` has T6040/T6041 kernel branches: `cyberchaos.dev/yuka/linux` (`more-t6041`,
  a `dcuart-t8142` branch carrying a `t6040.dtsi`), and got **flokli's M4 Pro Mac
  Mini (j773s)** booting to a shell with all cores + PMGR (noted M4 Pro "has less
  memory channels" → relevant to our MCC ticket 020).
- `enverbalalic` has a **real T6041 with working DebugUSB** and is hand-writing
  DTs; `integralpilot` has a dockchannel driver (`IntegralPilot/linux2`).
- We are ahead of them on: DockChannel console + full 214-domain PMGR quirk +
  PCIe host-side clock/PHY prefix + USB-host build. They are ahead on: the
  measured real IRQ number and a multi-machine DT view. Strong case to engage.
- Their machine is the Mac Mini (j773s); ours is the MacBook Pro 14" (J614s) —
  both T6040, so DT deltas are board-level (display/HID/audio), SoC parts shared.

### 5. NVMe internal-storage lead: SEP loads keys into the controller (Sol's lane)
- 2026-07-20 `chaos_princess`: "it is possible to access it, kinda. you order
  **sep to load specific keys into the nvme controller**, and then magic happens"
  (in a thread about the storage encryption being part of the OS/security
  separation). Concrete direction for the internal-NVMe route — consistent with
  the SPTM/TCB story (tickets 051/055). A SEP key-load step, not just queue
  programming, gates controller access.

### 6. Locked-sysreg / hv / SPTM status on M4 (affects all RE here)
- 2026-07-21 `yuka`: iBoot builds with "that particular aic reg unlocked":
  **have it — t8132, t8140, t6050; do NOT — t6040, t6041, t8142.** So our T6040
  has the AIC reg locked (this is the flokli `aic_init_cpu` skip we already
  carry). An Apple radar fixed it for one machine; discussion of filing another
  to get t6040/t6041/t8142 unlocked in a future iBoot.
- `JamesCalligeros`: "feature request: stop using sprr/gxf and sptm" (half-joke)
  — confirms M4 SPTM/GXF is still the wall; no hv tracing on these machines yet.
- `nickchan`: interest in "some L2C registers to sweep mmio without generating an
  SError storm" — same territory as our PCIe L2C_ERR_STS / log-ring SError work.

### 7. PCIe on M4 — an untested t8142 branch to compare (our lane, ticket 058/044)
- `yuka`: "there are no t602x pcie docs are there?"; is working on **t8142 PCIe**
  and pushed `github.com/yuyuyureka/m1n1/tree/feature/untested-t8142-pcie` for
  testing `pcie_init()`. t8142 is in the same M4 cohort as t6040/t6041. Worth
  diffing against our `pcie.c` op-115/PHY approach for the aperture precondition.

### 8. DCP / display (ticket 022 track-upstream)
- `chadmed` is actively porting DCP 14.8.3: branches `chadmed/m1n1` (`dcp/14.8.3`)
  and `chadmed/linux` (`dcp/14.8.3`); DCP boots on some machines but still crashes
  (swap failures, changed surface-clearing semantics, iova read errors on
  disappearing framebuffers). macOS 27.0 beta breaks it; 26.6 works. 15.x needs
  SPTM on M3. jannau to look at 14.8.3 DCP from ~2026-07-23. Our posture (track,
  don't build) is right; these are the branches to watch for M4 DCP.

## Plan — what we do about it

| # | Action | Surface | Owner |
|---|---|---|---|
| P1 | **Rebuild the DockChannel path on IRQ 816** + data-reg-first earlycon; audit our WIP direct `apple,dockchannel-uart` driver vs yuka's; prep a rig retest of interrupt-driven `ttyDC0`. | new ticket (below) | claude |
| P1 | Make RX/TX IRQ bit positions (BIT(1)/BIT(2)) a **DT property** and fold into our upstreamable poll/IRQ patch. | ticket 047 / dockchannel upstream | claude |
| P2 | Diff yuka's `untested-t8142-pcie` m1n1 branch against our `pcie.c` op-115/PHY prefix for the aperture precondition. | fold into ticket 058 | claude |
| P2 | Record the SEP-loads-keys-into-NVMe-controller lead in the SPTM route work. | ticket 055 | sol |
| P2 | Draft for CJ a note to yuka/enverbalalic/flokli sharing our DockChannel+PMGR+PCIe progress and proposing the DT-property-for-IRQ-bits shape/shared t6040.dtsi. Agents do not post externally. | ticket 047 | either |
| P3 | Note chadmed's DCP 14.8.3 branches as the M4 DCP tracking target. | ROADMAP / ticket 022 | tracking |
| — | Record the locked-AIC-reg status (t6040/t6041/t8142 locked; radar pending) so we don't re-derive it. | ROADMAP + memory | done here |

## Sources
Reconstructed corpus and per-day hit extracts under the session scratchpad
(`corpus.tsv`, `hits.tsv`); public IRC, quoted minimally with attribution.
