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

## Separate, unchanged fact

The ticket-096 forward/reverse decode is still incomplete (`0x14` semantics, raw
masks, cached-command/interrupt/power-config/repeater coordination). That is a
completeness question about the *sequence*, tracked in 096 — it is not a danger
statement and should not be quoted as one.

## Bounds for an exploratory run

Capture pre-state with an R0-class read, keep the passive stick as the only
right-port device, stop at the first unexpected reply, and expect a full shutdown
afterwards.

## Language discipline for future notes

Distinguish **volatile state needing a power cycle** (cheap and routine in this
workflow) from **persistent/non-volatile change** (would require flash/OTP/patch
writes, which are out of scope and absent from the decoded op set). Do not write
"unrecoverable", "brick", or "permanent damage" without naming the specific
non-volatile mechanism that would cause it.
