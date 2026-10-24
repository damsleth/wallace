# Ticket 305 attempt 2026-10-24: blocked on the host, KIS link unavailable

Claude, CJ attending. **The target was never chainloaded.** No Linux boot,
no SPMI, no PD transaction.

Setup per CJ: M4 at `Running proxy`, DebugUSB cable left port ↔ host left
port, S128 in the M4's right port. All 305 payload hashes re-verified
(`Image-usb2pd.buildA` `5a136710…`, physfix DTB `eaf8cceb…`,
`initramfs-sdroot-hardened` `4cc65133…`, chainload m1n1 `7de07c71…`).
Lease acquired as `claude`.

## What happened

1. `t6040-debugusb-console.sh` with no argument: the VDM sequence succeeded
   (unlock → DBMa → debug USB → exit). kisd then logged a repeating
   `could not open device for exclusive access (error 0xe00002c5)`.
   `t6040-proxy-alive.py`: no reply.
2. One bounded recovery, `T6040_KEEPALIVE=1 … reboot`: the VDM reboot into
   normal mode, reconnect and debug-USB entry all succeeded. kisd hit the same
   exclusive-access error, and the script reported no `Running proxy` within
   25 s, since nothing could read the stream.
3. Host registry: the M4's "Debug USB" device (`05ac:1881`) is enumerated,
   with `IOUserClientCreator = "pid 984, deviceinterfaced"`.
   `deviceinterfaced` is
   `/Library/Apple/System/Library/PrivateFrameworks/DeviceInterface.framework/Support/deviceinterfaced`,
   started 2026-10-24 18:16. Host is macOS 15.8.1 (24H32). Exactly one kisd
   was running.

Conclusion: a host system daemon now claims the KIS device, so kisd cannot
open it. No 305 evidence about the M4 resulted. The agent may not stop a root
Apple daemon or change system settings, so this needs CJ.

Lease released **wedged** (`NEEDS_RECOVERY`). The target took one sanctioned
VDM reboot into the enrolled rollback m1n1 and is presumed at its proxy; that
is unverified because the link is down. kisd log copy:
`linux-build-out/kisd-console-20261024-claude-305-blocked.log` (`0e4123ac8a167347…`).

## To resume

CJ frees the device: for example, quit whatever app is driving
`deviceinterfaced`, unload or kill that daemon, or reboot the host and check
`ioreg` shows no `deviceinterfaced` client on `Debug USB`. Then the next
holder runs the normal recovery boot, `rig-lease.sh recovered`, and
re-attempts 305 unchanged.
