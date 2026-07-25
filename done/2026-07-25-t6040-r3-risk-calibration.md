# T6040 R3 risk calibration — correcting an overstatement (2026-07-25)

Maintainer challenged an agent (claude) claim that running R3 "could leave the
right USB-C port's PD controller in an unrecoverable state". **That claim was
wrong and is withdrawn.** This note records the calibrated position so no future
agent inherits the overstatement.

## What is actually true

- **No persistent-brick mechanism exists in the staged HPM op set.** This was
  already the documented conclusion (`done/2026-07-24-t6040-spmi-risk-policy-review.md`:
  *"No persistent-brick mechanism has been identified in the staged HPM
  operations. The credible failures are a dead right port, timeout, lost events,
  proxy wedge, or power-cycle recovery."*). An independent re-check of the decode
  corpus for the real brick vector — flash / OTP / patch-bundle / non-volatile
  config writes — found **none**. The decoded operations are runtime only:
  register RMW plus 4CC runtime commands (`disablePort()` on `0x28`,
  `repeaterReset()`).
- **The SN201202x is a PD microcontroller with volatile runtime state.**
  Role/VBUS/mask/event state lives in its RAM and `AppleHPM` performs a full
  initialization every macOS boot, so a power cycle re-establishes a known state.
- **The fixture is correct and not an electrical hazard.** J614s port layout
  (maintainer-confirmed 2026-07-25): the M1<->M4 cable is on the **top-left DFU
  port** on both hosts; the **single right-side port holds only the passive
  bus-powered USB stick**. Applying VBUS to a passive sink is the normal designed
  host operation, and VBUS on the right port cannot reach another host.

## The cost that remains, and why it is cheap

The realistic worst case is that the right port stays in an odd state (VBUS
latched on, W1C event state consumed, masks unrestored) **until a power cycle**.

That costs us essentially nothing: the bring-up workflow already power-cycles the
machine constantly — every `t6040-debugusb-console.sh reboot`, every chainload
cycle, every recovery boot. A state that clears on power cycle is inside the
normal operating loop, not an incident.

## So why is R3 still not the next thing to run?

**Not for safety reasons — for expected-value reasons.** The *forward* sequence is
incomplete, not just the reverse:

- the address-`0x14` mutation semantics are unresolved;
- the interrupt masks "must remain raw rather than being assigned guessed Type-C"
  meanings;
- cached-command, interrupt ordering, power/config coordination and repeater
  sequencing are unresolved (`tickets/096`, ticket 023 notes).

Building R3 today therefore means issuing SPMI writes derived from *guessed*
semantics, with a low probability of achieving enumeration. The trade is "probably
learn nothing, possibly cost a power cycle" — a poor trade now, and a good one as
soon as the decode fills in. That decode is the actual critical path.

## Practical consequence

- R3 stays gated on the ticket-096 decode, and the recorded reason is
  **incompleteness of the forward path**, not fear of permanent harm.
- If the maintainer chooses to run an exploratory R3 anyway, that is a reasonable
  call. Sensible bounds: capture pre-state with an R0-class read, keep the passive
  stick as the only right-port device, stop at the first unexpected reply, and
  expect a full shutdown afterwards.
- Language discipline for future notes: distinguish **volatile state needing a
  power cycle** (cheap, routine here) from **persistent/non-volatile change**
  (would need flash/OTP/patch writes, which are not in scope and not present in
  the decoded op set). Do not use "unrecoverable", "brick", or "permanent damage"
  without naming the specific non-volatile mechanism that would cause it.
