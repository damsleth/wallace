# T6040 USB physical-port ADT capture attempt (2026-07-21)

Approved rig ticket 057 was attempted by `codex`. The ADT reader itself never
started because the DebugUSB recovery bar was not reached.

## Outcome

1. Ticket 057 was approved by CJ and the rig lease was acquired with helper
   hash `b6e74236`.
2. `RIG_AGENT=codex scripts/t6040-debugusb-console.sh reboot` completed the
   macvdm normal-mode reboot and DebugUSB switch, but timed out after 25 seconds
   without seeing `Running proxy`.
3. A clean `T6040_KEEPALIVE=1` attachment kept `kisd` and the pty reader alive;
   `kisd` remained at `Waiting for device` and no proxy bytes arrived.
4. That process group was stopped before any further action. No second kisd or
   reader remained.
5. Per the no-retry-on-wedge rule, no further reboot was attempted. The lease
   was released `--state wedged`; the rig now reports `NEEDS_RECOVERY`.

No ADT file or filtered log was created. The reviewed Python helper did not
run, no target RAM was read or written, Linux did not boot, and no USB, MMIO,
PMU/SPMI/NVRAM, or storage path was initialized.

Ticket 057 remains approved but incomplete. Before retrying it, the next lease
holder must perform the standard recovery boot, confirm a stable `Running
proxy`, and mark the rig recovered. Do not combine that recovery with the USB
host smoke.

## Follow-up attachment check

The maintainer later confirmed that the M4 display showed `Running proxy`.
`codex` reacquired the lease and ran a keepalive KIS attachment without another
reboot. The host-side result remained negative: `kisd` stayed at `Waiting for
device`, `/tmp/m1n1-console.log` received no bytes, and no plain
`/dev/cu.usbmodem*` fallback appeared. This distinguishes a healthy local m1n1
proxy from a missing host transport. The keepalive process group was stopped,
the lease was again released wedged, and no ADT read occurred. The maintainer
offered a physical power cycle as the next recovery action.

The maintainer then power-cycled the M4 and again confirmed `Running proxy` on
its display. A third clean KIS attachment attempt produced the same host-side
result: macvdmtool switched the target to DebugUSB successfully, but `kisd`
remained at `Waiting for device`, no console bytes arrived, and no plain USB
serial fallback existed. This points to the physical DebugUSB path (DFU port,
SBU-capable DP/TB cable, or KIS device presentation), not m1n1 execution. No
further reboot or live experiment was attempted.

## Resolution

The maintainer moved the tether to the previously proven top-left/rear Type-C
port and cold-started the M4. KIS then attached immediately. Ticket 057 ran to
completion; its capture hash and controller-to-port mapping are recorded in
`done/2026-07-21-t6040-usb-port-map-adt-result.md`.
