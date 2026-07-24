# T6040 SPMI risk-policy review

Date: 2026-07-24

Scope: captured J614s ADT, current m1n1 SPMI implementation, Yuka's
`tps6598x-spmi` branch, paired AppleHPM/AppleSPMI evidence, and public
SPMI/USB-C behavior. No rig or target access.

## Decision

The maintainer approved replacing Wallace's blanket "never write SPMI" rule
with `docs/SPMI_SAFETY.md`.

SPMI is a command transport whose risk depends on the selected controller,
slave, opcode, register, and connected fixture. PMU, charger, NVRAM,
firmware/flash, AOP-SPMI, RESET, unknown endpoints, scanning, and blind logical
register access remain prohibited. Exact, reviewed non-PMU transactions are
deny-by-default but no longer categorically impossible.

## J614s isolation evidence

The exact 606,208-byte ADT
(`7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`)
places the system PMUs on `nub-spmi0/1/2`. The right Type-C manager is isolated:

```text
/arm-io/nub-spmi-a1
  Gen3, reg[0] = 0x309198000 / 0x4000
  sole child /arm-io/nub-spmi-a1/hpm2
    usbc,sn201202x,spmi
    SID 0x0c, rid 2, right, port 3
```

There is no PMU sibling on that controller. `nub-spmi-a0` is deliberately
excluded because it contains left-back DebugUSB HPM0, left-front HPM1, and
unidentified class-11 HPM5.

## Risk classification

- A bounded Register-0 selector plus one-byte HPM status read changes only
  transient transport selection state and has very low physical risk.
- HPM WAKEUP and `SSPS` to S0 are volatile operating-state changes: low
  physical risk, moderate functional risk, and separately gated.
- Interrupt-mask writes can be restored, but an all-ones W1C event clear loses
  state and is not approved.
- Role/VBUS/config/eUSB2/ATC writes can alter connector power and require a
  passive-sink fixture plus a proved detach/rollback path.
- No persistent-brick mechanism has been identified in the staged HPM
  operations. The credible failures are a dead right port, timeout, lost
  events, proxy wedge, or power-cycle recovery. Persistent writes and
  PMU/charger access stay out of scope.

The current Yuka branch remains unsuitable wholesale because it iterates
HPM1/HPM2/HPM5, automatically sends WAKEUP and SHUTDOWN, may `SSPS`,
clears/masks interrupts, and contains unbounded/error-lifetime problems.

## Ticketed experiment ladder

- 092: offline build and cross-review of separate direct-HPM2 R0/R1/R2
  artifacts.
- 093: R0 selector plus one-byte logical power-state `0x20` read.
- 094: R1 WAKEUP plus conditional `SSPS` S0.
- 095: R2 exact interrupt-mask save/change/restore with no W1C event clear.
- 096: offline class-10 attach/detach, VBUS, repeater, and ATC rollback decode.
- 097: R3 passive-stick right-port host-link proof and no-root enumeration.
- 098: corrected OpenRC persistent-root image.
- 099: tethered persistent-root proof, then a separate untethered boot.

The policy change authorizes preparation and proposal of these exact stages;
it does not approve any rig ticket or allow generic SPMI experimentation.
