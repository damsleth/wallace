# T6040 right-HPM2 R2 SSPS-to-S0 result (2026-07-24)

Ticket: 095
Result: **PASS at the intended class boundary; rig recovery remains required**

## Exact candidate

```text
m1n1-hpm2 commit:
  276f4059d8c4130ce56525f263afa1ef110447d1
binary:
  /Users/damsleth/Code/linux-build-out/t6040-hpm2-276f4059d8c4/r2/m1n1.bin
binary SHA-256:
  23737cd31407c1046fb3c4e56e3a34f898ea845b8e98b978a98166eafe32b271
transcript:
  /Users/damsleth/Code/linux-build-out/hpm2-r2-ssps-s0-20260724.log
transcript SHA-256:
  630fe61aa8d8701a3e39968470cdc9a9789077d454a1a0749c09f76aee2272a5
```

An independent clean rebuild and source/machine-code review passed before the
run. The deployable BIN and Mach-O reproduced exactly. The reviewer verified
that the candidate contains exactly two extended-write sites: one byte
`0x00` to logical DATA1 (`0x09`) and four bytes `53 53 50 53` (`SSPS`) to
logical CMD1 (`0x08`). No IntMask, IntClear, W1C/event, role, VBUS, USB
configuration, PHY, ATC, DWC3, xHCI, or storage path is linked.

## Observed transaction boundary

The exact right-HPM2 identity gate passed. WAKEUP ACKed, the selector window
became active, and the initial logical system-power-state read returned
`0x07`. The candidate then:

1. selected logical DATA1 `0x09` and wrote exactly `00`;
2. selected logical CMD1 `0x08` and wrote exactly `53 53 50 53`;
3. observed command completion without a transport error;
4. read the final logical power state as `0x00`; and
5. printed `HPM is in S0`, classified the run R2 PASS, and intentionally
   warm-rebooted.

This proves the public-driver WAKEUP + SSPS sequence can move J614s right HPM2
from state `0x07` to `0x00`. It does **not** prove connector role, source power,
the eUSB2 repeater, ATC PHY, DWC3/xHCI, device enumeration, or block access.

## Post-run recovery state

The class-boundary reboot itself was intentional. The subsequent standard
DebugUSB recovery command failed with `Failed to send VDM`. One bounded
reattach entered DebugUSB, but `kisd` did not attach and no console bytes
arrived. No further hardware action was attempted.

The lease was released as `wedged`; the canonical rig status is therefore:

```text
rig: FREE
rig: !! NEEDS_RECOVERY — link untrusted until a recovery boot + 'rig-lease.sh recovered <agent>'.
```

This is a recovery/observability failure after the successful HPM boundary,
not evidence that the SSPS transaction failed. It is also not yet safe to
attribute the failed reattach to SSPS: the next rig action must be a normal
recovery boot, followed by a healthy proxy confirmation and an explicit
`rig-lease.sh recovered <agent>` before any experiment resumes.

## Consequence

Ticket 095 is complete. The interrupt-mask experiment originally bundled into
its first plan was deliberately removed and remains untested. Any mask
save/change/restore work must be a later, separately built and reviewed
candidate. The next USB work should remain split into read-only post-S0 status,
mask handling only if evidence requires it, reviewed forward/rollback host
transition, enumeration, read-only block access, and finally bounded
filesystem writes.
