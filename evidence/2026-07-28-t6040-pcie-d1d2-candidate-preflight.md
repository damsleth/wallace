# Ticket 124 preflight — PCIe candidate adding Apple's two missing pre-PHY-IP ops (D1+D2)

Status: **built and reproducible; NOT reviewed, NOT approved, NOT run.** Needs the cross-agent
exact-artifact review (COORDINATION.md) and CJ's attended session — this candidate performs two
new hardware writes to the PCIe clkgen/PHY blocks, and a bad PHY write can wedge the tether.

## Hypothesis under test

Every T6040 PCIe run hangs at the same place: the **read half** of the first
`apcie-phy-ip-pll-tunables` RMW at reg[3]+0x90 (`0x417040090`) never returns — a
non-responding PHY-IP aperture. (Note: the full decode,
`evidence/2026-07-28-t6040-initializephy-full-decode.md`, established this is an RMW *setting*
bit 0, not a PLL-lock poll — `_applyTunablesFromData` has no poll semantics. The earlier
"poll" reading came from m1n1's own diagnostic label, and the hang is the aperture, not a
lock that never comes up.)

The decode found **exactly two Apple operations that precede the first PHY-IP access and that
m1n1 omitted**:

- **D1** — `clkgen[0] |= BIT(5)`: `_enableRootComplex()` sets it immediately after
  `_configPciePLLs()` returns and strictly before the final (PHY) clock gate. m1n1 went from
  the PLL-lock poll straight to the gate. A plausible PhyIP clock enable.
  Evidence: kernelcache `0xfffffe0009b36224–0xb36254`.
- **D2** — the PHY release clears **BIT(4)**, not BIT(7): m1n1's `APCIE_PHY_CTRL_RESET`
  (bit 7) is a t602x constant; on T8132 Apple clears bit 4 there and never touches bit 7.
  Evidence: `0xfffffe0009b37380` (`and w8, w8, #0xffffffef`).

Also included: **D5**, Apple's 1 µs delay before the CLK1 request (timing only, no new
register). Deliberately **excluded** so the probe stays the pass/fail line: D6 (PhyIP[0x90]
bit-16 clear) and D7/D8 (tail bit-27 + poll position) — they run *after* the first PHY-IP
access and are the follow-up once the aperture responds. **D3 is settled offline:** the J614s
ADT `lane-cfg` is 0 (read from the captured `j614s-usb-port-map-20260721.adt`), so m1n1's
existing `rc_base+0x4 = 0` write is already Apple-equivalent.

## New hardware surface, precisely

Two write deltas, both RMWs on registers m1n1 already writes in the proven prefix, both at
ADT-derived bases (clkgen = apcie reg[6] `0x415044000`; shared-PHY = reg[2], PhyPhy window
+0x8000):

| op | register | old behavior | new behavior |
|---|---|---|---|
| D1 | clkgen+0x0 | untouched after PLL lock | `set32(…, 0x20)` |
| D2 | PhyPhy+0x0 | `clear32(…, BIT(7))` | `clear32(…, BIT(4))` (t6040 only; other SoCs unchanged) |

The PHY-IP probe itself is **unchanged and read-only** (`tunables_read_first_local_addr_trace`),
and the code still returns before any PHY-IP write and before all port/Linux-PCIe work.

## Artifact

- m1n1 `main` commit `19edc72b` ("pcie: add the two T6040 pre-PHY-IP operations Apple
  performs"), mirrored to the curated `m1n1-clean` `t6040-bringup` series (`9c35cd2c`, on top
  of the also-backfilled `fb4eea73` = ticket-058 clkgen commit).
- Binary: `~/Code/linux-build-out/m1n1-t6040-pcie-d1d2-19edc72b.bin`, SHA-256
  `0e065589c08a6c3186c0bc3eddeae9078a3d878597db60965b88511eb881daad`, version tag
  `t6040-pcie-d1d2-19edc72b85fc`, **two byte-identical clean builds** from committed state.

## Run plan (attended, CJ present — same harness as ticket 068)

1. Fresh proxy: `bash scripts/t6040-debugusb-console.sh reboot`.
2. Boot exactly as 068 was run (PCIe kernel DT `t6040-j614s-dcuart-pcie`), with this m1n1.
3. Watch for the new transcript lines, in order:
   `pcie: T6040 clkgen[0] bit 5 (pre-gate, Apple _enableRootComplex)` →
   `pcie: T6040 PHY %d bit-4 released (Apple T8132 sequence)` →
   `pcie: T6040 PHY-IP probe with D1+D2 applied (ticket 124)`.
4. **PASS** = `tunable: apcie-phy-ip-pll-tunables[0] read value=0x… done` followed by
   `pcie: T6040 PHY-IP aperture RESPONDED; stopping before write`. The aperture hypothesis is
   confirmed; follow-up ticket applies the PLL/AUSPMA tunables + D6/D7/D8 and re-runs.
5. **FAIL** = hang after the probe line again. D1+D2 alone are insufficient; recovery is the
   sanctioned DebugUSB reboot (identical to every prior op-115 run). Next candidates are the
   D4 ordering delta (Apple applies apcie-common tunables + lane-cfg *after* clkgen/gate-7;
   m1n1 before) and a deeper look at `enableDeviceClock` index mapping.
6. Either way: record the transcript in `evidence/`, update ticket 124, release the rig healthy.

Known bounded risks: the two new RMWs touch the clkgen and shared-PHY blocks that all prior
runs already wrote without SError; the failure mode observed for this path has always been a
hang recovered by DebugUSB reboot, not an SError. No storage, port, or Linux-PCIe surface is
reachable (hard return before ports).

## Gates

1. Cross-agent exact-artifact review (`sol`) against `~/Code/m1n1/AGENTS.md`: ADT-derived
   addresses, no new aperture, intentional stop before the next operation class, hash pinned.
2. CJ plan approval + attended slot.
