# T6040 DockChannel bounded RX-IRQ telemetry — result

Run once 2026-07-14 by `fable` under approved rig ticket 001 (cross-review:
`done/2026-07-14-t6040-rxirq-image-cross-review.md`; artifact record:
`done/2026-07-14-t6040-dockchannel-rxirq-txpoll.md`). **Clean bounded result;
no retry.** One boot, one marker-triggered `IRQ_BIT1_PROBE` injection.

## Exact booted set (hashes re-verified immediately before boot)

- m1n1 control (chainloaded): `m1n1-t6040-logbuf-upper-guard-dryrun.bin`,
  SHA-256 `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`
  (`a61fd099`, zero-PCIe-write + proven log-ring upper guard)
- `Image-dcuart-irq-txpoll`
  `ef60d5ea681e1b5d8a999be448aaf7326c546aaf76350d803fbbafd40114a15e`
- `t6040-j614s-dcuart-irq-txpoll.dtb`
  `3d5bc90e74e609b0337474063c62c139de928c6b8c468057d03c68611d08d452`
- `initramfs-dcuart-irq-txpoll-report.cpio.gz`
  `4697a5b6ebc88c5c123854d268da45ae919b1672d9dd58e4554e627362770263`

Transcript: `logs/t6040-console-20260714-dockchannel-rxirq-txpoll.log`,
SHA-256 `2fca14570939da4f9eacfb2568fb317e4a9637f75bb96088a63b37a109969ee2`
(81 lines).

## Live result

Boot reached BusyBox; the diagnostic printed its banner, the baseline sample,
and the `INJECT-NOW` marker. Exactly one LF-terminated `IRQ_BIT1_PROBE` line
was injected after the marker. All ten one-second samples then arrived over
polled TX (the relay itself was flawless), followed by the full report.

Every sample, baseline through 10, was identical:

```text
virq=42 hwirq=65896 rx_count=0x0 irq_flag=0x0 irq_mask=0x2 total=0 rx=0 tx=0
none=0 capped=0 cap_total=0 ... hard=0 ...
```

- the handler **never entered** (`total=0` — not one RX, TX, or spurious
  entry);
- the raw local `IRQ_FLAG` stayed `0x0` and the mask held `0x2` (RX BIT(1)
  enabled) for the whole window;
- `DATA_RX_COUNT` stayed `0x0` at every sample — the injected bytes never
  appeared in the AP-side FIFO;
- `/proc/interrupts` before and after:
  `42: 0 AIC2 65896 Level 50880c000.mailbox` — zero count on the correctly
  joined line;
- userspace RX: `received=<none>`;
- neither storm cap triggered (validly unused — there was nothing to cap).

## The number-space join (a real correction to the pre-run note)

The pre-registered note claimed die-0 input 360 translates to *numeric hwirq
360*. Live, the AIC driver encodes IRQ hwirqs as `((die + 1) << 16) | input`,
so die-0 input 360 displays as hwirq **65896** (`0x10168`), virq 42. The
telemetry's explicit `virq=42 hwirq=65896` join is what makes the zero count
in `/proc/interrupts` interpretable — a bare scan for a "360" row would have
found nothing and proven nothing.

## Pre-registered interpretation (matrix row 3)

> no cap; no RX count/flag; no `/proc/interrupts` delta; FIFO remains zero
> after injection → **bytes did not reach this build; investigate mask-write
> or pre-handoff perturbation, not AIC delivery.**

The failure is *upstream of the interrupt*: the probe bytes never entered the
FIFO, so whether AIC input 360 can deliver was **not exercised** at all. The
old "dead IRQ 360" claim remains unpublishable — but so does the IRQ-storm
hypothesis: with zero handler entries there was no reassertion to observe.

The sharpest new question is a build-delta one: the earlier TX-only reporter
(`done/2026-07-14-t6040-dockchannel-irq-tx-report.md`) **did** receive the
probe line once in an IRQ-mode build, while this build — whose only material
RX-side differences are the telemetry counters, TX BIT(2) never being
unmasked, and probe/startup IRQ-block writes identical in sequence — saw no
byte arrive. Candidate perturbations to analyze offline (static, no rig):
the dock-side KIS agent's flow-control interaction with the AP-side
IRQ_MASK/RX_THRESH state, and any ordering difference in the probe/startup
writes between the two builds. This is the follow-up ticket's scope; no live
retry of this image is permitted or useful.

## Rig state

The sanctioned DebugUSB reboot restored a fresh, quiescent `Running proxy`;
released `--state healthy`. Ticket 001 closed.
