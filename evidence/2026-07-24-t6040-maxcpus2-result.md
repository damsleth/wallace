# T6040 ticket 005 maxcpus=2 result (2026-07-24)

Result: **FAIL at the bounded no-console stop; do not retry unchanged**.

The exact independently reviewed ticket-005 set ran once after a healthy KIS
proxy recovery:

| Input | SHA-256 |
|---|---|
| m1n1 | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| Image | `a6c2f09354bf1d61559b450f9430eb06d42f94d027d539c2deade708d708c4ff` |
| DTB | `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814` |
| initramfs | `160cd9bdc8b75f10243124c1baea7ae0f4cd9e45b7284b948681e74edd8e90ea` |

The effective boot arguments were:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel maxcpus=2 rdinit=/init
```

m1n1 started its known 14-core WFE park, completed the Linux preparation,
armed the watchdog, printed `Ready to boot`, shut down its three USB
controllers, disabled the MMU, and vectored to the exact kernel entry. After
that boundary the DockChannel log remained exactly 184 bytes and contained
only the m1n1 handoff:

```text
Preparing to run next stage at 0x10010a00000...
USB0: shutdown
USB1: shutdown
USB2: shutdown
MMU: shutting down...
MMU: shutdown successful, clearing caches
Vectoring to next stage...
```

No Linux line, SMP reporter marker, reset text, or SError appeared during the
35-second observation window or the following bounded check. The pass
conditions were therefore not met. A normal DebugUSB reboot immediately
restored a quiescent `Running proxy`.

Evidence hashes:

- `dcuart-chainload.log`:
  `7606cd23add01203651ea3793e96de883e00fe308ae6bf28a981f338e425103a`
- `dcuart-boot.log`:
  `b497ebc9e63c40c08a3d656488f0ed5dcabad5d66c6acd7dc9f3388f6674767c`
- `dcuart-console.log`:
  `2108fcc9657c24c247ab7a63542297d7c7a9d8a8e9f30108e6aefe3a0766609f`

This is evidence for a Linux failure correlated with enabling the first
secondary and occurring before the polling DockChannel driver becomes
visible. It does not by itself prove that the secondary-start path caused the
failure, nor that the reporter or CPU-1 liveness test ran. Tickets 120/121 and
cpufreq ticket 006 remain blocked. The next step is an offline
early-output/secondary-start diagnosis and a separately reviewed candidate;
do not rerun this image unchanged.
