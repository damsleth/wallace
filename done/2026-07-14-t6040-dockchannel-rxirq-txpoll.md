# T6040 DockChannel-UART RX-IRQ / TX-poll diagnostic

Prepared offline 2026-07-14 after the first TX-only scheduled reporter lost
its output following the RX probe. **Not approved or run.** This diagnostic
keeps RX interrupt-driven on BIT(1), but makes TX completion independent of the
shared AIC line so the storm guard cannot suppress the evidence relay.

## Exact build

- proven zero-PCIe-write m1n1 control: SHA-256
  `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`
- `Image-dcuart-irq-txpoll`: SHA-256
  `0c8a4d9e240b0b8fd2e64a63c7448c203d55cd970aecb552cca225df01a865cf`
- `System.map-dcuart-irq-txpoll`: SHA-256
  `993bd4c3855dafbffd1c3c7b88c8e9747fdb78ef28fe149259b9b33a6d17ffb9`
- `t6040-j614s-dcuart-irq-txpoll.dtb`: SHA-256
  `feb4de7c91746790d1dd31945091ba992f9634845441bafe4daa7320de7e15b9`
- `initramfs-dcuart-irq-txpoll-report.cpio.gz`: SHA-256
  `1e242e659631318e4b3247cccdfafaa3ace0e2a2c2e4b25fad5c7ada1a7491d2`
- embedded init source: SHA-256
  `e8116bd6d4e9310c018b84335044bee2a621460bb13810591564b854e7023ea8`
- incremental TX-poll patch: SHA-256
  `af8015a59ba6f6293c427b653863bef1a8d331780bd6c997e44c53b1c76ee445`

The kernel and all three diagnostic DTBs built successfully in the fresh
container tree `/build/linux-dcuart-irq-txpoll`. The incremental patch passes
checkpatch with zero errors and zero warnings. The extracted `/init` hash
matches `scripts/t6040-init-dcuart-irq-txpoll-report`.

## Driver and MMIO boundary

The diagnostic DT inherits the reviewed RX BIT(1) configuration and adds only
the local `apple,tx-poll-mode` bring-up property. MTP remains on TX/RX
BIT(2)/BIT(3). UART probe and startup retain the exact previous writes:

- `0x50880c000 = 0` (mask all during probe);
- `0x50880c004 = 0xffffffff` (clear flags, W1C);
- `0x508828004 = 1` (RX threshold);
- `0x50880c004 = 0x2` (clear RX BIT(1), W1C);
- `0x50880c000 = 0x2` (enable RX BIT(1)).

Unlike the previous image, UART TX never enables BIT(2), does not program the
TX interrupt threshold, and does not use the AIC line for completion. It writes
the same known TX FIFO registers, then polls only the already-used
`DATA_TX_FREE` register at `0x50882c014` every 1 ms while a message is active.
When the FIFO becomes empty it reports completion to the mailbox core.

The unchanged 4,096-entry RX storm guard still writes zero to
`0x50880c000` and calls `disable_irq_nosync(360)` on entry 4,097. TX polling
does not re-enable that line or write another mask value, so the guard remains
strictly bounded while the evidence relay can continue.

The decompiled DT was verified to contain UART TX/RX masks `0x4/0x2`, storm
limit `0x1000`, `apple,tx-poll-mode`, and no full `apple,poll-mode`. Its kernel
contains both the guard message and `polling TX completion; RX remains
interrupt-driven`. The DT has no PCIe or NVMe node.

## One-run measurement

Boot once with the exact artifacts above. After the unique instruction banner
appears, wait six seconds and inject exactly one line:

```text
IRQ_BIT1_PROBE
```

The initramfs takes `/proc/interrupts` snapshots before and after a ten-second
window with no reporter TX, records whether its one background read received
the line, then sends both snapshots and the DockChannel dmesg tail using polled
TX completion. Interpret the bounded outcomes as follows:

- guard message/count 4097: RX BIT(1) produces a storm on this configuration;
- a small interrupt delta plus `received=IRQ_BIT1_PROBE`: IRQ RX works;
- a small delta but `received=<none>`: hard IRQ fires but delivery fails later;
- no delta and no receive: AIC input 360 did not deliver the RX event;
- output still stops: the failure is below mailbox TX-completion accounting.

Recover after the report or immediately on silence. Do not retry the same
image. No storage namespace is present or accessed.

## Approval gate

This image changes TX completion from the previous shared IRQ path to a bounded
poll of the existing safe `DATA_TX_FREE` register. It requires fresh explicit
approval for one boot of the exact hashes above and one injection of the exact
probe line. No live run of this image has occurred.
