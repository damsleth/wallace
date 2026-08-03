# T6040 ticket 073 DockChannel IRQ-816 result (2026-07-24)

Result: **PASS**.

The exact independently reviewed ticket-073 set ran once:

- m1n1 `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`
- Image `a6c2f09354bf1d61559b450f9430eb06d42f94d027d539c2deade708d708c4ff`
- DTB `21a3446830a50a0d739a6e55e2ef9f9ee3986bcc677d12e5caceced708cf22a2`
- initramfs `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`

Linux reached the BusyBox `ttydc0` shell with `apple,poll-mode` absent. Two
host-written command batches were received, echoed, and executed:

```text
IRQ816_RX_OK
IRQ816_STABLE_OK
```

The second batch followed a 12-second stability interval. `/proc/interrupts`
reported the DockChannel mailbox as IRQ 42 with 652 handled events at capture
time:

```text
42:        652     AIC2 66352 Level     50880c000.mailbox
Err:          0
```

There was no interrupt storm, watchdog reset, SError, or lost console. A
normal DebugUSB reboot then restored a quiescent `Running proxy`.

Evidence hashes:

- `dcuart-chainload.log`:
  `dacce859bb5c755caaa5a703e879b821d60a34423ce3ed55c437619598fc72f7`
- `dcuart-boot.log`:
  `0162bb04d7a2212972c2d39e190f5ed31299d1eb9a108229e3deabca83ef8ad8`
- `dcuart-console.log`:
  `b789bb36d2e69c58410d97039b73cc0e9d15d2b4d8cf846583a5bc048881bff2`

This closes the corrected AIC-input experiment: interrupt-driven DockChannel
RX works on the J614s path. Polling remains a conservative fallback, but IRQ
816 is now a live-proven feature for later integration.
