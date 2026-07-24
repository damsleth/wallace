# T6040 SPMI safety policy

Approved by the maintainer: 2026-07-24

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

No R2 interrupt-mask experiment has run. It was deliberately removed from
ticket 095's SSPS-only binary. Create it only if the host-transition decode
shows that mask ownership must change.

### Class R3: connector role, VBUS, and PHY transition

HPM logical addresses `0x14`, `0x23`, `0x24`, and `0x55`, Type-C role/source
policy, VBUS/VCONN, eUSB2 repeater, and ATC PHY writes require a complete
host-transition and detach/rollback design. They are not permanently banned,
but each exact sequence is separately gated.

The 2026-07-24 final ticket-096 decode found paired software-object removal
and framework-managed eUSB2/ACIO semantic shutdown, but no VBUS-off operation,
race-safe inverse for `0x14` plus W1C/cache state, exact mask/detect
restoration, or restoration of the observed pre-SSPS state `0x07`. This is an
explicit R3 no-go. Do not build or run tickets 102–108 until new primary
evidence closes those boundaries.

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
