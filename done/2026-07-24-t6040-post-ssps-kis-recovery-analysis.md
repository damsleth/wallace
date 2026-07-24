# T6040 post-SSPS KIS recovery analysis (ticket 118)

Date: 2026-07-24

Result: **recovery control passed after the maintainer's power cycle; no causal
attribution to right-HPM2 SSPS**.

## Evidence boundary

Ticket 095 itself completed successfully and logged final right-HPM2 power
state `0x00` before its intentional warm reboot. The later failure occurred in
the recovery transport:

1. the standard host VDM command returned `Failed to send VDM`;
2. one bounded DebugUSB re-entry reported success at the host command layer;
3. `kisd` did not attach and no console bytes arrived; and
4. the lease was released `wedged` without another target operation.

No mask/W1C, connector-role, VBUS, repeater, ATC, USB, or storage code was in
the ticket-095 binary. The changed endpoint was right-port HPM2; KIS uses the
separate left-back HPM0 path. This makes a direct same-endpoint explanation
unsupported, but does not rule out a broader Type-C/firmware state interaction.

The failure also does not match the common unread/canonical PTY wedge
signature: that signature attaches `kisd`, produces roughly 15 KB ending in
the binary startup prefix, then loses proxy replies. Here `kisd` never attached
and there were no bytes. Nor does it prove a target crash: the failed VDM
preceded any new proxy transaction.

## Recovery control

The maintainer power-cycled the M4 and reported `Running proxy`. With the rig
lease held, the host then:

- started one fresh `kisd`, created a raw `/tmp/m1n1` PTY, and attached exactly
  one drain reader;
- entered DebugUSB successfully and observed `Device opened`;
- paused the drain reader and ran the standard read-only T6040 health check;
- received chip ID `0x6040`, ADT size `0x94000`, `broken_wfi=True`, and valid
  E/P cluster power-state reads; and
- resumed the reader and cleared `NEEDS_RECOVERY`.

Several later normal DebugUSB reboot/re-entry cycles also returned quiescent
`Running proxy` states. This proves the rig and both recovery transports are
currently healthy. It does not distinguish whether the earlier failure was a
transient host/VDM/KIS condition or Type-C state cleared by the power cycle.

## Exact recovery-control checklist

1. Hold the rig lease. Keep DebugUSB physically on left-back and the passive
   test stick on right; attach no charger, dock, other host, or powered source.
2. Ensure there is only one `kisd` and one PTY drain reader. Kill stale
   readers/daemons before creating a fresh pair.
3. Run `RIG_AGENT=<holder> T6040_KEEPALIVE=1
   scripts/t6040-debugusb-console.sh reboot`.
4. Require all of: VDM success, `Running proxy` within 25 seconds, three stable
   one-second console-size samples, and `kisd` `Device opened`.
5. Pause—not duplicate—the reader. Run
   `M1N1DEVICE=/tmp/m1n1 proxyclient/experiments/t6040.py`; require chip ID
   `0x6040`, a valid ADT, and the bounded health report.
6. Resume the reader, record `rig-lease.sh recovered <holder>`, and only then
   consider an approved+ready live ticket.
7. On VDM failure or no `kisd` attachment, stop after one bounded fresh
   reattach. Mark wedged. A physical power cycle is the next escalation; do not
   retry SPMI or infer that another HPM command is recovery.

Ticket 103 may therefore use a normal healthy recovery gate, but must still
wait for tickets 096 and 102. Its result must not claim that SSPS is harmless
to recovery merely because this post-power-cycle control passed.
