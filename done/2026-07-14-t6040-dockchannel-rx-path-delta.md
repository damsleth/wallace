# T6040 DockChannel-UART RX ingress build-delta analysis

> **Superseded routing note (2026-07-21):** this comparison remains useful for
> its FIFO/flow-control observations, but both live images used ADT input 360.
> The real UART interrupt is AIC input 816. Do not proceed to the proposed
> timing follow-up unchanged. See `done/2026-07-21-asahi-dev-log-review.md`.

Ticket 049 compared the two completed IRQ-mode runs without touching the rig:

- the TX-only reporter, whose kernel accepted the single host probe before
  losing its TX report (`done/2026-07-14-t6040-dockchannel-irq-tx-report.md`);
- the bounded RX-IRQ/TX-poll reporter, whose AP FIFO, local IRQ state, and AIC
  count all remained zero after its single host probe
  (`done/2026-07-14-t6040-dockchannel-rxirq-txpoll-result.md`).

The comparison does not support an RX startup-order difference. It leaves two
controlled confounders: the time at which the host injected relative to AP TX,
and whether the AP had exercised the legacy TX-threshold/IRQ-mask sequence.

## Exact artifacts and source states

The preserved output artifacts still match their records:

| Build | Image SHA-256 | DTB SHA-256 | Wallace source state |
|---|---|---|---|
| TX-only reporter | `de09f5a17229e97d7cb291fe1471e63d2925ef3e8057d5019e4d380c5509cdf6` | `676be63aa9b7f059fbef0bfb79a93bb5b49d554a42b3e7cd2b9ee9844fa906ab` | `07af2a2` plus the recorded report initramfs |
| RX-IRQ/TX-poll | `ef60d5ea681e1b5d8a999be448aaf7326c546aaf76350d803fbbafd40114a15e` | `3d5bc90e74e609b0337474063c62c139de928c6b8c468057d03c68611d08d452` | `7d788aa` |

The source delta that affects the mailbox consists of
`patches/t6040-dockchannel-tx-poll-debug.patch`,
`patches/t6040-dockchannel-fifo-telemetry-debug.patch`, and the diagnostic DT
properties. The intervening edit to the base dcuart DT is comments only.
Decompiling both preserved DTBs confirms the same UART resources, AIC input
360, TX mask `0x4`, and RX mask `0x2`.

## RX startup is identical

Both kernels perform this sequence for the UART mailbox:

1. probe writes `IRQ_MASK = 0`;
2. probe writes `IRQ_FLAG = 0xffffffff` (W1C);
3. the tty mailbox client opens and writes `RX_THRESH = 1`;
4. `apple_dockchannel_irq_enable(RX BIT(1))` first writes
   `IRQ_FLAG = 0x2` (W1C), then writes `IRQ_MASK = 0x2`;
5. the Linux virq is enabled.

The TX-poll and telemetry patches do not move any of those operations. Both
initramfs scripts open `/dev/ttydc0`, start their bounded background read, and
wait five seconds after their banners before the measurement. The new
telemetry reads `DATA_RX_COUNT`, `IRQ_FLAG`, and `IRQ_MASK` before injection,
but it does not write them. Its lower storm limits cannot affect pre-injection
state because the live handler count was zero.

Therefore neither `RX_THRESH` timing nor RX mask/W1C ordering explains why the
second run saw no ingress.

## Material AP-side delta

The old reporter used interrupt-driven TX completion for every banner write.
Each send:

1. wrote the AP TX FIFO;
2. wrote `CONFIG_TX_THRESH = 0x800`;
3. W1C-cleared TX BIT(2), then changed `IRQ_MASK` from RX-only `0x2` to
   RX+TX `0x6`;
4. on FIFO empty, the hard handler returned the mask to `0x2` and W1C-acked
   the pending TX flag.

The host waited six seconds after the last instruction line before injecting.
Thus the old build had exercised several complete TX IRQ cycles and was
quiescent at injection.

The TX-poll build still wrote the same AP TX FIFO, but never wrote
`CONFIG_TX_THRESH`, never W1C-cleared TX BIT(2), and never added TX BIT(2) to
`IRQ_MASK`. Its marker-triggered probe was injected immediately after the host
received `INJECT-NOW`; one-second telemetry output then continued. Receiving
the marker proves those bytes had left the AP FIFO, but does not prove that the
reverse direction tolerates an immediate direction change or concurrent AP TX.

These are separate hypotheses:

- **timing/turnaround:** host-to-AP ingress was dropped because the injection
  followed AP output immediately rather than after the old six-second quiet
  interval;
- **legacy TX priming:** programming `TX_THRESH` and/or exercising TX BIT(2)
  changes bridge state needed for later host-to-AP ingress.

The completed runs cannot distinguish them.

## Dock-side KIS flow-control audit

The host daemon does not inspect or modify the AP mailbox's IRQ block or
threshold registers. In `kisd/src/main.rs`, host-to-target traffic:

1. queries `DATA_TX_FREE` through the KIS PAM portal at the dock-side UART
   aperture;
2. writes the selected dock-side `DATA_TX8/16/24/32` register with a KIS
   physical-address write;
3. tracks only the returned dock-side capacity.

The joined RX task independently receives PPM portal packets for target-to-host
traffic. There is no software path from AP `IRQ_MASK` or `RX_THRESH` into
kisd's capacity calculation. m1n1's safe `dockchannel_uart.c` likewise polls
only its ADT-derived UART data FIFO and does not establish an IRQ/threshold
contract before Linux handoff.

This rules out direct **software** flow-control coupling. It does not rule out
an undocumented bridge/hardware dependency on AP TX threshold or direction
turnaround.

## Next bounded discriminator

Use an ordered two-step ladder; do not retry either completed artifact.

1. **Timing-only image first.** Reuse the telemetry kernel and DT unchanged,
   but replace the initramfs with a silent-window reporter. It prints one
   instruction marker telling the host to wait six seconds, emits no ttydc TX
   for ten seconds, accepts exactly one `IRQ_BIT1_PROBE`, then reports the same
   FIFO/flag/mask/AIC telemetry over polled TX. This changes no kernel MMIO and
   matches the old reporter's proven quiescent injection timing. A successful
   ingress attributes the discrepancy to turnaround/concurrent TX, not AIC or
   mask programming.

2. **Only if step 1 still shows zero ingress**, prepare a separately reviewed
   legacy-TX-prime variant. It must retain TX-poll reporting and add only the
   already-used `CONFIG_TX_THRESH = 0x800` plus a bounded TX BIT(2) W1C/mask
   pulse that returns `IRQ_MASK` to `0x2` before the same silent window. Record
   mask readback before injection. This tests the AP register-history
   hypothesis without depending on TX IRQ delivery for the evidence relay.

Each step needs a fresh initramfs/kernel/DT hash set, static MMIO review,
cross-review, and explicit approval before one boot. Do not combine the two
steps: changing timing and TX priming together would preserve the ambiguity.

## Conclusion

Ticket 001 did not exercise AIC delivery because ingress never occurred. The
static delta audit further shows that RX setup itself did not change and that
kisd has no direct AP-mask flow-control dependency. The first useful follow-up
is therefore the no-new-MMIO timing-only discriminator; legacy TX priming is a
second gated experiment, not the default explanation.
