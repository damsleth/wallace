# T6040 dual-mode object — LIVE PASS, both halves (2026-07-25)

Ticket 140. Enrolled `m1n1-b0-alpine-dualmode.bin`
(`b409d89e85d309edb79defe01465c094fa642d5643a004a81c54c3e862f5bb5a`, 9.03 MiB,
578 pages), m1n1 v6 `c10a502f` with `EARLY_PROXY_TIMEOUT=10`,
`EARLY_PROXY_UNCONDITIONAL`, `FB_CONSOLE_ALWAYS`.

## Half 1 — nobody connects: Alpine boots

Maintainer cold-booted with no host attached: the object waited, timed out, and
reached the Alpine shell exactly as in milestone B0.

## Half 2 — host connects inside the window: m1n1 hands over control

Watcher armed on the M1 (poll for the gadget every 200 ms, then hammer the
handshake), maintainer rebooted:

```text
Boot policy: sip0 = 0
Bringing up USB for early debug...
USB0/USB1/USB2 initialized
Waiting for proxy connection...  Connected!
m1n1 base: 0x100052f4000
[22:26:07] PROXY ATTACHED on attempt 1
  m1n1 base   = 0x100052f4000
  target-type = 'J614s'   model = 'Mac16,8'
  mem_size    = 0x5cb500000
```

m1n1 entered `uartproxy` and **did not boot the payload** — full chainload/debug
control on an enrolled, otherwise-untethered machine.

## What this proves that was previously unverified

- **The unconditional window arms on an enrolled cold boot.** `sip0 = 0` here, so
  upstream's `!display && sip0 == 127` gate could never have fired; the
  `EARLY_PROXY_UNCONDITIONAL` patch is what makes the door exist. Until now the
  window had only ever been observed on a *chainloaded* m1n1, because every earlier
  enrolled dual-mode object was 16 KiB-misaligned and never executed at all.
- **macOS enumerates the m1n1 gadget fast enough for a 10 s window** — attached on
  attempt 1. The earlier failures to see `/dev/cu.usbmodem*` were entirely due to
  m1n1 never running, not to enumeration latency. 10 s stands as the keeper value.
- **`fb_set_active(true)` before the window** makes the countdown visible on the
  panel (in v3/v4 it ran after the window, so the wait was invisible).

## Operating notes

- The window uses the m1n1 **USB gadget**, not DebugUSB/KIS; they are mutually
  exclusive on the DFU port. Plain cold boot with the cable attached, then
  `M1N1DEVICE=/dev/cu.usbmodemJ22GYCN4YG1`. Do not run `macvdmtool debugusb`.
- Untethered cost is **+10 s** per cold boot.
- After a deliberate attach, m1n1 stays in the proxy; reboot without connecting to
  get Alpine back.

Ticket 140 done. This is the daily-driver configuration: untethered Alpine with a
10-second debug door.
