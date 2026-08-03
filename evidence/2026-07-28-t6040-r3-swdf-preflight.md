# Ticket 105 preflight — R3 (SWDF host role swap) and R4 (SWUF inverse) candidates

> **2026-07-28 — THIS PREFLIGHT IS WITHDRAWN. NO-GO.** Cross-review by `sol`
> (`evidence/2026-07-28-t6040-r3-r4-crossreview-no-go.md`) found three defects in it:
> 1. **`SWDF` is a data-role swap (DFP), not a power-role swap.** The source/sink commands are
>    `SWSr`/`SWSk`. So this artifact **cannot establish VBUS sourcing** and R4 cannot roll back a
>    source transition. The premise of the whole document — "swap to DFP ⇒ sources VBUS" — is an
>    unverified inference, and VBUS must not be inferred from a successful `SWDF`.
> 2. **It reads no role/orientation/VBUS state** — only the 4CC task result and HPM system power
>    state `0x20` — so tickets 105/106's required role/power transcript and byte-exact rollback are
>    absent, and the omission of passive-sink pre-detection had no approved replacement.
> 3. **My symbol-audit claim below was false.** I wrote that the binaries link no DWC3 code and that
>    the deny-list proves it. **Verified: 14 `usb_dwc3_*` symbols are linked**; the deny-list simply
>    never tested for them. (The experiment reboots before `usb_init()`, so that code does not
>    *execute* — but the assertion was wrong regardless, and the deny-list needs the pattern added.)
>
> The run that did happen was also unobservable — see
> `evidence/2026-07-28-t6040-r3-swdf-blind-run-no-transcript.md`. Keep this file only as the record of
> what was built and why it was rejected.

Status: **DRAFT — build pending the independent 4CC review.** Hashes and review verdicts are
filled in below when they exist; this document is not a run authorization until every
`PENDING` is resolved and CJ approves the attended session.

## What R3 is

One bounded hardware action: command the right-port HPM (SN201202x class-10,
`/arm-io/nub-spmi-a1/hpm2`, SID `0x0c`) to swap to **DFP (host/source)** so the port sources
VBUS to the attached passive bus-powered stick. Decoded basis:
`evidence/2026-07-28-t6040-roleswap-decoded-swdf-swuf-confirmed.md` — `AppleHPMInterface::roleSwap(0)`
issues the 4CC **`SWDF`** to CMD1 (`0x08`) via `execute4Cc`; `roleSwap(1)` issues **`SWUF`**
(back to UFP/device), the inverse.

## The candidates

`~/Code/m1n1-hpm2` `src/t6040_hpm2.c`, extending the live-proven R0/R1/R2 experiment classes:

- **Class 3 (R3, forward):** exact R2 ladder (fail-closed ADT identity gate → `spmi_init_strict`
  → WAKEUP → read power state `0x20` → SSPS to S0 if needed → verify S0) **plus**:
  write one `0x00` byte to DATA1 `0x09` (mirroring the reviewed macOS `atomic4CC` call shape —
  and the R2 SSPS shape), then 4CC `{'S','W','D','F'}` (`0x53 0x57 0x44 0x46`) to CMD1 `0x08`;
  poll CMD1 as u32 until
  `0` (complete) or `0x444d4321` (`!CMD`, rejected), 500 ms budget (5000 × 100 µs; PD
  renegotiation is slower than SSPS's 100 ms); on completion read DATA1 `0x09` (4 bytes, byte 0
  = task result, 0 = success) and re-read power state (expect still S0); hold 10 s for VBUS
  observation; PASS/FAIL banner; warm reboot (unchanged `main.c` flow).
- **Class 4 (R4, inverse):** identical, 4CC `{'S','W','U','F'}` (`0x53 0x57 0x55 0x46`) — the
  decoded rollback to UFP/device. Built and hashed alongside R3 so an inverse artifact exists
  before the forward run; run only if needed.

New SPMI surface versus R2: **none** — same endpoint, same logical registers
(CMD1 `0x08`, DATA1 `0x09`, power-state `0x20`), same select/read/write primitives. The only
deltas are the 4CC constant, the longer completion poll, the DATA1 read-back (a read of a
register R2 already wrote), and the 10 s observation hold.

## Safety framing (unchanged from the calibrated 2026-07-25 position)

- Fixture: the M1↔M4 tether is on the top-left DFU port; the right port holds only the passive
  bus-powered stick. Sourcing VBUS to a passive sink is the designed host operation; VBUS cannot
  reach another host. (`evidence/2026-07-25-t6040-r3-risk-calibration.md`)
- No persistent-brick mechanism exists in this op set: register RMW + runtime 4CC only, no
  flash/OTP/patch-bundle writes. Worst realistic case is odd port state (VBUS latched, role
  stuck) **until a power cycle**, which the workflow performs routinely.
- Fail-closed behaviors: ADT identity mismatch → zero SPMI transactions; selector timeout,
  `!CMD`, poll timeout, or post-swap power-state change → FAIL, stop, warm reboot. No retry
  loops, no second command after an unexpected reply.
- Forbidden surface untouched: no PMU/charger/NVRAM/firmware writes, no mask/W1C writes, no
  eUSB2/ATC/xHCI/PHY code linked (build audit enforces by symbol deny-list).

## Gates before the attended run

1. **Independent byte-level 4CC review — PASSED (2026-07-28).** All four questions answered from
   a fresh re-derivation (verdicts recorded in the addendum of
   `evidence/2026-07-28-t6040-roleswap-decoded-swdf-swuf-confirmed.md`): (a) polarity CONFIRMED,
   roleSwap(0)→SWDF is host/DFP; (b) CONFIRMED no DFU/flash 4CC exists anywhere in the
   kernelcache — the only 1-byte neighbor of SWDF is SWUF itself; (c) byte order CONFIRMED,
   two cancelling reversals put forward-ASCII `53 57 44 46` on CMD1, the R2 convention;
   (d) REFINED — macOS writes one `0x00` byte to DATA1 before CMD1, and the candidate was
   updated to match (commit `e41cf6e4` in `m1n1-hpm2`).
2. **Reproducible build + audit — DONE (2026-07-28).** `scripts/t6040-build-hpm2-candidates.sh`
   (now builds classes 0–4) passed: two byte-identical clean builds per class, symbol allow list
   present (`t6040_hpm2_experiment`, `spmi_init_strict`, `spmi_reg0_write`, `spmi_ext_read`,
   `spmi_send_wakeup`, `spmi_ext_write`) and deny list absent (no `spmi_send_reset/sleep/shutdown`,
   no `tps6598x*`, no `usb_init`/`usb_phy_bringup`, no long-form SPMI ops). Constant audit on the
   final binaries: r2 contains only `SSPS`; r3 adds exactly `SWDF`; r4 exactly `SWUF`. Hashes below.
3. **CJ approves and runs attended** on the 096/097 framework: fresh proxy via
   `scripts/t6040-debugusb-console.sh reboot`, chainload the R3 m1n1, watch the transcript,
   power-cycle recovery available. Ticket 106 is the plan-approved live slot; it lists
   096/103/104/105 as gates — the SWDF decode resolves the forward/inverse-semantics gap those
   gates tracked, but CJ decides whether 106's approval carries or a fresh approval is wanted.

## Expected transcript (PASS path)

```text
t6040-hpm2: ticket 105 class R3 (SWDF role swap to host), direct endpoint only
t6040-hpm2: ADT identity PASS, direct endpoint /arm-io/nub-spmi-a1/hpm2 sid=0x0c
t6040-hpm2: WAKEUP sid=0x0c
t6040-hpm2: power-state=0x07            (or 0x00 if already active)
…SSPS ladder as in R2, ending…
t6040-hpm2: HPM is in S0
t6040-hpm2: issuing role-swap 4CC "SWDF"
t6040-hpm2: role-swap task result 00 xx xx xx
t6040-hpm2: power-state=0x00
t6040-hpm2: role swap complete, HPM remains in S0
t6040-hpm2: holding 10 s for VBUS observation
t6040-hpm2: class R3 PASS; intentional stop and warm reboot
```

Observable success beyond the transcript: any activity/power LED on the stick during the 10 s
hold. Electrical VBUS confirmation and enumeration belong to the follow-on tickets (108/109),
not this run.

## After the run

- PASS or FAIL, record the transcript in `evidence/` and update tickets 096/105/106.
- If PASS: the port may remain DFP with VBUS on across the warm reboot (HPM state is volatile
  only to power cycle). That is expected; note it, don't treat it as an anomaly. R4 (SWUF) or a
  power cycle restores device role.
- Do not chain into enumeration/xHCI experiments in the same session unless CJ explicitly
  chooses to; 108+ are separate tickets with their own artifacts.

## Build hashes

Source: `m1n1-hpm2` branch `codex/t6040-hpm2-stages`, commit
`e41cf6e4ee8f2a8b0edbc3fc917ef42aee22e894` ("experiments: add HPM role-swap classes R3 (SWDF)
and R4 (SWUF)"). Artifacts: `~/Code/linux-build-out/t6040-hpm2-e41cf6e4ee8f/` (full SHA256SUMS
per class alongside each binary; captured-ADT identity pinned in MANIFEST).

| class | m1n1.bin SHA-256 |
|---|---|
| R3 (SWDF, forward/host) | `a106f8cd36a6068fc9586924028b9a64aca986a8e635e1bb0964422ec7345c4e` |
| R4 (SWUF, inverse/device) | `61d5f18ca19ca961162d3cae63a2352912a0683b44bca0ae4ef774c24e5a0716` |

Attended run, after a fresh proxy (`bash scripts/t6040-debugusb-console.sh reboot`):

```bash
bash scripts/t6040-boot-raw-object.sh ~/Code/linux-build-out/t6040-hpm2-e41cf6e4ee8f/r3/m1n1.bin a106f8cd36a6068fc9586924028b9a64aca986a8e635e1bb0964422ec7345c4e
```

(R4 inverse, only if wanted afterwards: `r4/m1n1.bin`
`61d5f18ca19ca961162d3cae63a2352912a0683b44bca0ae4ef774c24e5a0716`.)
