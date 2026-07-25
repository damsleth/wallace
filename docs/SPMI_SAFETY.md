# T6040 SPMI safety policy

Approved by the maintainer: 2026-07-25 (supersedes 2026-07-24)

SPMI is a transport, not a single risk class. Transactions are deny-by-default,
but an exact, ADT-verified non-PMU endpoint may be approved when its controller,
SID, operation, bounds, fixture, and recovery behavior are all explicit.

## Absolute prohibitions

- Never write PMU, charger, battery-management, RTC/scratchpad, NVRAM,
  firmware/flash, or other persistent state through SPMI or any other
  transport.
- Never issue transactions to an unknown endpoint, scan SIDs, blind-probe
  logical registers, or derive a controller address from another SoC.
- Never issue SPMI `RESET`, or an HPM firmware/update/unlock/flash command.
- Never treat a controller-command MMIO write as harmless merely because the
  requested slave operation is a read. Every SPMI read is initiated by a write
  to the controller command FIFO.

The captured J614s ADT keeps the system PMUs on `nub-spmi0`, `nub-spmi1`, and
`nub-spmi2`. Those controllers and their `pmu,spmi`/`pmu,abbey` children remain
completely out of scope. `aop-spmi0`, `nub-spmi3`, and `nub-spmi4` are also
prohibited unless a future policy revision names an exact endpoint.

## Current non-PMU allowlist

The sole endpoint eligible for reviewed experiments is the right-side Type-C
manager:

```text
controller path: /arm-io/nub-spmi-a1
compatible:      aapl,spmi
generation:      3
controller reg0: 0x309198000 / 0x4000
sole child:      /arm-io/nub-spmi-a1/hpm2
child compatible: usbc,sn201202x,spmi
SID:             0x0c
rid:             2
port-number:     3
port-location:   right
```

The exact captured ADT is 606,208 bytes with SHA-256
`7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`.
An experiment must fail closed unless every property above matches. It must
address the path directly; generic HPM iteration is not an allowlist.

`nub-spmi-a0` is not allowlisted. It contains HPM0 (left-back/DebugUSB), HPM1
(left-front), and HPM5 (class 11/port type 17). Touching it risks the recovery
tether or an unidentified function and provides no value to the right-port
test.

## Operation classes

### Class R0: read-equivalent, lowest physical risk

An exact logical-register read may use the SN201202x selector protocol:

1. SPMI Register-0 Write to select one named logical register.
2. Bounded polling of selector register `0x00`.
3. Bounded extended read from data window `0x20`.

This is not literally write-free: the selector is transient HPM state and the
controller command FIFO is written. It is eligible because it neither changes
PMU state nor requests a USB-C power/role transition. The first candidate may
read only logical system-power-state register `0x20`, one byte, with no
automatic wake or retry escalation.

### Class R1: HPM operating-state changes

SPMI `WAKEUP` and the HPM `SSPS` command targeting S0 are low physical-risk but
state-changing. They require their own exact ticket and artifact review. They
must not be silently added as fallback behavior to an R0 test.

SPMI `SLEEP` and `SHUTDOWN` remain prohibited until a test proves the prior
state and an exact restoration contract. A reboot is recovery, not proof of an
inverse.

Live evidence on 2026-07-24: exact right-HPM2 WAKEUP activated the selector
window and exposed power state `0x07`; the separately reviewed DATA1 `00` +
CMD1 `SSPS` sequence then produced state `0x00`. This proves only HPM S0.
It does not authorize role/VBUS/config, interrupt handling, PHY, or storage.

### Class R2: interrupt/event handling

Saving/restoring an interrupt mask can be reviewed, but clearing W1C event
registers destroys information and is not automatically reversible. The
existing generic path's all-ones `IntClear1` plus zero `IntMask1` sequence is
not approved. Any R2 candidate must name each register, preserve the original
mask, avoid broad event clear, and describe handoff to Linux.

On this part the registers are `IntEvent1` = `0x14` (9 bytes, read),
`IntMask1` = `0x16` (8 bytes on class 10), and `IntClear1` = `0x18` (9 bytes,
W1C). Note that the class-10 host-transition path in R3 below reaches `0x18`
and `0x16` on its own, so an R3 candidate inherits these R2 requirements
whether or not it is labelled an interrupt experiment.

No R2 interrupt-mask experiment has run. It was deliberately removed from
ticket 095's SSPS-only binary. Create it only if the host-transition decode
shows that mask ownership must change.

### Class R3: connector role, VBUS, and PHY transition

HPM logical addresses `0x14`, `0x16`, `0x18`, `0x23`, `0x24`, `0x50`, and
`0x55`, Type-C role/source policy, VBUS/VCONN, eUSB2 repeater, and ATC PHY
writes require a complete host-transition and detach/rollback design. They are
not permanently banned, but each exact sequence is separately gated.

The 2026-07-25 decode (`done/2026-07-25-t6040-hpm2-rollback-evidence.md`)
established which of these the macOS class-10 path actually touches, so each is
named with its exact operation:

- **`0x50` (data control) — written, and the sharp edge.** `clearDpIRQ()`
  performs a blind 4-byte full-word write of `0x00002000`, with no prior read
  and no saved value, and it is reached unconditionally from
  `setCurrentModeFlags()` on every mode-flag reset. `resetDataControl()` is the
  preserving variant but still discards the low 16 bits. An R3 candidate must
  read and save the full 4-byte word before any mutation, and must carry a
  reviewed position on whether writing a saved word back can re-assert the
  W1C-style bit 13.
- **`0x18` (`IntClear1`, 9 bytes) — written**, as the W1C half of
  `getAndClearInterrupt(0x14 -> 0x18)`. This is an R2-class event clear reached
  from an R3 path, so the R2 rules above apply to it in full. It has no inverse:
  `0x14` is never written anywhere in the paired driver.
- **`0x14` (`IntEvent1`, 9 bytes) — read only.** The earlier claim that the
  class-10 host transition *writes* `0x14` was a mis-decode and is withdrawn:
  the `raw[1] |= 0x0d` / `raw[7] |= 0x08` masks are applied to a software
  buffer, not to hardware. Reading it still consumes event state via the paired
  `0x18` clear, so it is not free.
- **`0x16` (`IntMask1`, 8 bytes) — written** by `setInterruptMask()` as a fully
  synthesized constant. macOS never reads `0x16` on this class and never saves
  the prior mask, so there is no restoration sequence to copy. R2 applies.
- **`0x23`, `0x24`, `0x55` — not reachable from class 10 at all** in macOS;
  their only callers gate on `hpm-class-type` 16/17. They stay gated here, and
  the absence makes them *more* hazardous rather than less: an artifact writing
  them would have no reference sequence, no readback path for `0x55`, and no
  proven neutral value.

This remains an explicit R3 no-go and ticket 096 is still open. No VBUS-off
operation exists in either direction (macOS has no VBUS primitive at all on this
port); the `0x18` W1C consumption is irreversible; and there is no restoration
for the interrupt mask, the detect state, or the observed pre-SSPS state `0x07`.
Apple performs no cross-layer teardown on detach, so there is no composition
order to copy for HPM <-> eUSB2 repeater <-> ATC PHY <-> ACIO/DWC3 either. Do
not build or run tickets 102–108 until new primary evidence closes those
boundaries.

R3 tests may use only a known passive sink such as the bus-powered USB memory
stick. Never attach a charger, powered dock, another host, or any externally
powered source during an unproven source-role/VBUS experiment.

## Requirements for every live SPMI experiment

- Hold the Wallace rig lease and obtain explicit maintainer approval for the
  exact artifact hash.
- Pin and verify the m1n1 commit, binary hash, ADT identity, controller path,
  generation, base, child compatible, SID, and port location.
- Address only `nub-spmi-a1/hpm2`; do not iterate buses, HPMs, or SIDs.
- Bound every FIFO wait, selector poll, command poll, and retry. Fail closed on
  any unexpected reply, value, timeout, or leftover FIFO entry.
- Log the exact SPMI opcode, SID, logical register, length, data (for writes),
  response, and stop boundary.
- Change one operation class per experiment. An R0 failure must not fall
  through to WAKEUP, SSPS, IRQ, VBUS, or PHY actions.
- Keep DebugUSB on left-back/HPM0 and the test device on right/HPM2.
- Stop on SError, timeout, unexpected reset, loss of recovery transport, or any
  access outside the manifest. Recover with the documented warm reboot, then a
  power cycle if necessary.

Current recovery status: ticket 095 passed but its following VDM/KIS recovery
did not. Ticket 118 later completed a healthy proxy control after a maintainer
power cycle and recorded the exact fail-closed checklist. The transient remains
unattributed; every later SPMI experiment still requires a fresh healthy proxy
check and normal recovery gate.

## Current upstream candidate

Yuka's `tps6598x-spmi` branch at `dcc5f1bccbbe986099f218e9057f7fa99a0b1fe2`
is an implementation lead, not an approved live artifact. It recognizes the
correct Gen3/SN201202x topology, but it iterates HPM1/HPM2/HPM5, automatically
sends WAKEUP and SHUTDOWN, may issue `SSPS`, clears/masks interrupts, and has
unbounded/error-lifetime issues. Wallace experiments must extract and harden
only the operation needed for the current stage.

The detailed topology and source audits are:

- `done/2026-07-24-t6040-hpm-spmi-discovery-boundary.md`
- `done/2026-07-24-t6040-hpm-class10-host-transition.md`
- `done/2026-07-24-t6040-yuka-hpm-spmi-branch-audit.md`
- `done/2026-07-24-t6040-hpm2-r2-ssps-s0-result.md`
