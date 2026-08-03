# T6040 DockChannel-UART bounded RX-IRQ telemetry

> **Superseded routing note (2026-07-21):** this historical image used ADT
> input 360. Bounded M4 Pro measurement later found the real UART interrupt at
> AIC input 816. The observations below remain valid, but they did not test the
> UART's AIC route. See `done/2026-07-21-asahi-dev-log-review.md`.

Prepared offline 2026-07-14 after the first TX-only scheduled reporter lost
its output only after RX data was injected. **Not approved or run.** This
replacement leaves RX interrupt-driven on BIT(1), makes TX completion
independent of the AIC line, caps the suspected storm inside the hard handler,
and reports FIFO/local-IRQ state once per second.

## Exact build

- proven zero-PCIe-write m1n1 control: SHA-256
  `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`
- `Image-dcuart-irq-txpoll`: SHA-256
  `ef60d5ea681e1b5d8a999be448aaf7326c546aaf76350d803fbbafd40114a15e`
- `System.map-dcuart-irq-txpoll`: SHA-256
  `119ad813b9d74b50f8272de317dc9208bc84b742d459e6b5423517b3f373d02e`
- `t6040-j614s-dcuart-irq-txpoll.dtb`: SHA-256
  `3d5bc90e74e609b0337474063c62c139de928c6b8c468057d03c68611d08d452`
- `initramfs-dcuart-irq-txpoll-report.cpio.gz`: SHA-256
  `4697a5b6ebc88c5c123854d268da45ae919b1672d9dd58e4554e627362770263`
- embedded init source: SHA-256
  `07d21482bbb132f7400caf811f0a9e7110ddbab829089d8ae6d76a6993230304`
- incremental TX-poll patch: SHA-256
  `af8015a59ba6f6293c427b653863bef1a8d331780bd6c997e44c53b1c76ee445`
- incremental FIFO/IRQ telemetry patch: SHA-256
  `29a8d9dad3090a11698ea1e94dd1ee83df95e553010762f4beae6d0bd803063d`

The kernel and diagnostic DTBs built successfully in the fresh container tree
`/build/linux-dcuart-irq-telemetry`. The telemetry patch applies after the
existing IRQ guard and TX-poll patches and passes strict checkpatch with zero
errors and zero warnings. The extracted `/init` hash exactly matches
`scripts/t6040-init-dcuart-irq-txpoll-report`.

The decompiled DT was verified to contain UART TX/RX masks `0x4/0x2`, AIC
specifier `<0 0x168 4>` (input 360, level high), hard cap `0x400` (1,024), RX
cap `0x3e8` (1,000), `apple,tx-poll-mode`, and
`apple,irq-telemetry`, with no full `apple,poll-mode`. The base DT's NVMe node
is present but disabled; there is no enabled PCIe or storage path in this
diagnostic.

## Bounded handler and telemetry

Probe/startup retains the reviewed UART writes:

- `0x50880c000 = 0` (mask all during probe);
- `0x50880c004 = 0xffffffff` (clear flags, W1C);
- `0x508828004 = 1` (RX threshold);
- `0x50880c004 = 0x2` (clear RX BIT(1), W1C);
- `0x50880c000 = 0x2` (enable RX BIT(1)).

UART TX never enables BIT(2) or uses the AIC line for completion. It writes the
same known TX FIFO registers and polls only `DATA_TX_FREE` at `0x50882c014`
every 1 ms while a message is active.

At the 1,000th handled RX BIT(1) event, the hard handler snapshots raw
`IRQ_FLAG`, `DATA_RX_COUNT`, and total-entry count, removes BIT(1) from its
local mask, and reads the mask back. It then performs the driver's existing W1C
of the pending event and permits that event's threaded drain. If handler
entries nevertheless continue, absolute entry 1,024 snapshots `IRQ_FLAG` and
`DATA_RX_COUNT` again, writes zero to the local mask, and calls
`disable_irq_nosync()` on the Linux virq. The maximum intended post-cap delta
is therefore 24 entries. No printk is issued from either cap path.

The read-only sysfs sample reports:

- current `DATA_RX_COUNT` at `0x50882c02c`;
- current raw local `IRQ_FLAG`/`IRQ_MASK` at `0x50880c004/0x50880c000`;
- total, RX, TX, and no-enabled-pending handler counts;
- the cap and hard-disable flag/FIFO snapshots, mask readback, and post-cap
  delta;
- Linux virq and its translated AIC hwirq.

These are all registers already used by the reviewed FIFO driver. The initramfs
samples them once per second over polled TX for ten seconds, then dumps
`/proc/interrupts` and the RX result.

## IRQ number-space and ACK audit

The DT, AIC scan, and new test refer to the same hardware input. The DT uses
`interrupts = <AIC_IRQ 360 IRQ_TYPE_LEVEL_HIGH>`. For die 0 the AIC domain
translates that specifier to numeric hwirq 360, and the old 0..4095 scan read
AIC HW_STATE input 360. `/proc/interrupts` instead shows the allocated Linux
virq; the driver logs and sysfs output provide the explicit `virq -> hwirq`
join before any zero count is interpreted.

Safe m1n1 commit `a61fd099` only reads/writes the UART FIFO data block at
`0x508828000` plus its known offsets. It never touches the UART IRQ block at
`0x50880c000`, so it cannot leave BIT(3) in the mask before Linux handoff.

The older working DockChannel/HID stack (`origin/neo`) defines UART-style RX as
BIT(1). Its parent irqchip explicitly W1C-acks the child flag, the RX hard
handler disables/masks that child, and the threaded callback then reads the
FIFO count and consumes a complete packet before re-arming RX. It therefore
does not support a drain-before-ACK requirement. The material delta is that the
current mailbox driver W1C-acks and wakes its drain thread while leaving RX
locally unmasked. This run measures whether reassertion stops once RX is
masked, without changing the existing ACK semantics first.

## One-run measurement

Boot once with the exact artifacts above. The initramfs waits five seconds,
takes the baseline, and emits this unique marker:

```text
[irq-txpoll] INJECT-NOW: send exactly IRQ_BIT1_PROBE<LF>
```

Only after that marker, inject exactly one LF-terminated line:

```text
IRQ_BIT1_PROBE
```

The pre-registered interpretation matrix is in `docs/NEXT_STEPS.md`; it was written
before the live observation. A smooth boot with cap entry 1,000 and hard entry
1,024 already latched is a valid microsecond-scale storm capture, not grounds
for a rerun. Recover after the report or immediately on silence. Do not retry
the same image.

## Approval gate

This replacement adds reads of the already-used FIFO count and local IRQ
registers, masks RX BIT(1) at event 1,000, and hard-disables the Linux virq at
entry 1,024. It requires fresh explicit approval for one boot of the exact
hashes above and one exact marker-triggered probe injection. No live run of
this image has occurred.
