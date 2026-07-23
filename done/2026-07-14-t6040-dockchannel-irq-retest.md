# T6040 DockChannel-UART RX BIT(1) IRQ retest

> **Superseded routing note (2026-07-21):** this historical image used ADT
> input 360. Bounded M4 Pro measurement later found the real UART interrupt at
> AIC input 816. The observations below remain valid, but they did not test the
> UART's AIC route. See `done/2026-07-21-asahi-dev-log-review.md`.

Prepared and run once on 2026-07-14 with explicit approval for UART TX BIT(2)
and RX BIT(1). The corrected mask did not restore host-to-target input: Linux
reached BusyBox and TX remained healthy, but neither of two short host commands
was echoed or answered. The 2026-07-12 all-AIC scan is still not sufficient to
call the UART interrupt dead because it enabled the FIFO using MTP's RX BIT(3).
The corrected run could not read `/proc/interrupts`, so it also does not show
whether AIC input 360 fired.

## Exact build

- proven zero-PCIe-write m1n1 control: `a61fd099`
  (`v1.6.0-75-ga61fd099`), SHA-256
  `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`
- kernel `Image-dcuart-irq` SHA-256:
  `de09f5a17229e97d7cb291fe1471e63d2925ef3e8057d5019e4d380c5509cdf6`
- `System.map-dcuart-irq` SHA-256:
  `d8e31b81d837d770c40c8fd94cbc6f7222d524f7006897b2dae7acd0cdb83c71`
- diagnostic DTB SHA-256:
  `676be63aa9b7f059fbef0bfb79a93bb5b49d554a42b3e7cd2b9ee9844fa906ab`
- DebugUSB initramfs SHA-256:
  `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`

The m1n1 binary is the already live-proven upper-log-guard dry-run control: it
prints the AXI trace but returns before all PCIe PMGR/controller MMIO, then boots
Linux. The DT has no PCIe or NVMe node.

## Driver and DT boundary

`t6040-dockchannel-poll.patch` now keeps the default MTP masks but permits each
instance to supply explicit `apple,irq-tx-mask` and `apple,irq-rx-mask` values.
The ordinary J614s DockChannel DT retains `apple,poll-mode` as the proven
fallback. The separate diagnostic DT removes only that property and describes:

| Instance | AIC IRQ | TX mask | RX mask | Mode |
|---|---:|---:|---:|---|
| MTP | 776 | `0x4` (BIT(2)) | `0x8` (BIT(3)) | existing IRQ path |
| UART | 360 | `0x4` (BIT(2)) | `0x2` (BIT(1)) | diagnostic IRQ path |

For the UART instance, probe performs the existing safe reset writes:

- `0x50880c000 = 0x00000000` (mask all)
- `0x50880c004 = 0xffffffff` (clear flags, W1C)

Mailbox startup then performs:

- `0x508828004 = 1` (RX threshold)
- `0x50880c004 = 0x2` (clear RX BIT(1), W1C)
- `0x50880c000 = 0x2` (enable RX BIT(1))

The first TX also uses the existing FIFO/data path, then writes threshold
`0x800`, clears TX BIT(2), and changes the IRQ mask to `0x6`. When TX empties,
the handler returns the mask to `0x2`. No unknown address or offset is added.

Because the motivating report includes IRQ storms, the diagnostic-only patch
`t6040-dockchannel-irq-guard-debug.patch` caps this instance at 4,096 handled
interrupts. On the 4,097th entry it writes zero to the already-used mask
register `0x50880c000`, calls `disable_irq_nosync(360)`, and emits one error.
This may make the diagnostic TTY silent, but prevents an unbounded CPU storm;
the sanctioned DebugUSB reboot remains the recovery path.

## One-run test

Boot once with the exact artifacts above. BusyBox output exercises UART TX.
Then send two short commands over `/tmp/m1n1` and capture their replies plus
the IRQ-360 line from `/proc/interrupts`; successful replies prove the RX path,
and an increasing count attributes them to the AIC interrupt rather than the
removed poll worker. Capture dmesg lines for both DockChannel instances and
confirm:

- UART reports masks `TX=0x4 RX=0x2` and the 4,096-entry guard;
- UART does not report `using polled mode`;
- MTP reports `TX=0x4 RX=0x8`;
- the storm guard does not trip.

If the TTY stays silent or the guard trips, stop and recover; do not retry the
same image. This test does not access NVMe or any storage namespace.

## Live result

The maintainer approved one boot of the exact hashes above with UART TX
BIT(2) and RX BIT(1). The image booted normally and printed the BusyBox banner,
which proves the UART TX path remained functional with its BIT(2) mask. The
host then sent exactly two commands, first terminated by LF and then by CR:

```text
echo RX_BIT1_ONE
echo RX_BIT1_TWO
```

Neither command was echoed or answered, and the target transcript remained
exactly 2,232 bytes. Following the pre-agreed stop rule, the image was not
retried. A sanctioned DebugUSB reboot restored a fresh, quiescent m1n1 proxy.
Linux never accessed NVMe or another storage namespace.

Transcript:
`logs/t6040-console-20260714-dockchannel-irq-bit1.log`, SHA-256
`698d3e51df4009ab3d254c7588ed3e70e309fb8003f8e6c937ef793b7890fe7c`.

This is a negative result for interactive RX with the corrected FIFO enable,
not yet a negative result for AIC input 360. Because RX was the path needed to
request `/proc/interrupts` and dmesg, the run captured neither the IRQ count nor
the diagnostic driver's internal count. The next useful test must report those
counts autonomously over the proven TX path before and after a bounded host-byte
injection. That offline follow-up is now built and separately gated in
`done/2026-07-14-t6040-dockchannel-irq-tx-report.md`. Keep poll mode as the
standard configuration and do not publish the old scan as a hardware erratum.

## Approval record

The maintainer approved one boot with TX BIT(2) and RX BIT(1); that single run
is complete. Any revised diagnostic or second boot requires a new exact review
and approval. The property names are local bring-up names pending coordination;
do not present them as an agreed upstream binding.
