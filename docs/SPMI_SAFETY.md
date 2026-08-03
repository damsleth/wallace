# T6040 SPMI safety policy

Current policy as of 2026-08-03; maintainer approval last changed 2026-07-29.

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

### Class R0: reads — ANY logical register on the allowlisted endpoint

**Reads are broadly permitted.** Any logical register of the allowlisted
right-port HPM may be read, at its natural length, using the SN201202x selector
protocol:

1. SPMI Register-0 Write to select the logical register.
2. Bounded polling of selector register `0x00`.
3. Bounded extended read from data window `0x20`.

Revised 2026-07-29: the previous text permitted *only* logical `0x20`, one byte.
That was too narrow — it forced a policy amendment for every new observation and
left us proposing experiments (e.g. reading Status `0x1a`) that the document did
not cover. Reading cannot change PMU state, cannot request a USB-C power/role
transition, and cannot alter persistent state, so the register number is not the
thing worth gating. Useful examples now explicitly in scope: Mode `0x03`,
CMD1 `0x08` (reading it returns command status; reading never executes a
command), DATA1 `0x09`, `IntEvent1` `0x14`, `IntMask1` `0x16`, Status `0x1a`,
system power state `0x20`, and port/role status registers.

A read is still not literally write-free — the selector is transient HPM state
and the controller command FIFO is written — so R0 keeps these bounds:

- The allowlisted endpoint only (`/arm-io/nub-spmi-a1/hpm2`, SID `0x0c`), with
  the full fail-closed ADT identity gate. Reads do not license SID scanning or
  a second endpoint.
- **Never write the data window `0x20`.** Selecting a register is permitted;
  writing its contents is R1 or higher.
- **Never W1C.** Reading `0x14`/`0x18` is fine; writing them destroys event
  state and is explicitly not R0.
- Bounded polls with an explicit timeout, and no escalation: an R0 failure must
  not retry into a write, a command, or a different register.

**The `WAKEUP` preamble is part of R0.** A bare read of most registers returns
`0x00` while the HPM is inactive (live evidence, ticket 093), so an R0 candidate
may send one SPMI `WAKEUP` to the allowlisted SID, wait a bounded delay, and then
read. `WAKEUP` is live-proven twice (tickets 094 and 095), changes no persistent
state, and a reboot restores the prior condition. Without this, a read-only
experiment is likely to return nothing and burn a rig cycle for no information.

### Class R1: HPM operating-state changes

The HPM `SSPS` command targeting S0 is low physical-risk but state-changing, and
requires its own exact ticket and artifact review. It must not be silently added
as fallback behaviour to an R0 test.

(`WAKEUP` moved to R0 on 2026-07-29: it is live-proven, non-persistent, and
without it most reads return `0x00`. It remains a deliberate, logged step, not an
implicit retry.)

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

This remains an explicit R3 no-go. Ticket 096 records the proposed R3 sequence
as withdrawn because it only selected data role and lacked a complete
rollback. No VBUS-off
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
- Change one operation class per experiment. Reading several registers in one
  R0 candidate is fine — that is one class. An R0 failure must not fall
  through to WAKEUP, SSPS, IRQ, VBUS, or PHY actions.
- Keep DebugUSB on left-back/HPM0 and the test device on right/HPM2.
- Stop on SError, timeout, unexpected reset, loss of recovery transport, or any
  access outside the manifest. Recover with the documented warm reboot, then a
  power cycle if necessary.

Ticket 118 completed a healthy proxy control after the earlier post-095
recovery failure. The transient remains unattributed; every later SPMI
experiment still requires a fresh healthy proxy check and normal recovery
gate.

## Current implementation lead

Yuka's `tps6598x-spmi` branch at
`dcc5f1bccbbe986099f218e9057f7fa99a0b1fe2` matches the
Gen3/SN201202x topology but is not an approved live artifact. Its generic
iteration, automatic power-state commands, interrupt mutation, and recovery
behavior exceed this allowlist.

Wallace has an offline, uncalled port of the transport on
`codex/t6040-spmi-transport` at
`74d3ccc705e7f5b1bddc055403f77f921890d289`. It deliberately does not run
from `usb_init()` and does not expose a proven VBUS-enable path. Any future
candidate must select only HPM2 and implement only the operation class named by
its ticket.

The detailed topology and source audits are:

- `done/2026-07-24-t6040-hpm-spmi-discovery-boundary.md`
- `done/2026-07-24-t6040-hpm-class10-host-transition.md`
- `done/2026-07-24-t6040-yuka-hpm-spmi-branch-audit.md`
- `done/2026-07-24-t6040-hpm2-r2-ssps-s0-result.md`
