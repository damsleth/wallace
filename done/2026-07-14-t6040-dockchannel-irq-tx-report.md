# T6040 DockChannel-UART TX-only IRQ counter diagnostic

Prepared offline 2026-07-14 after the corrected RX BIT(1) interactive run
remained silent. **Not approved or run.** This follow-up changes only the
initramfs behavior: it reuses the exact storm-bounded kernel, DTB, and
zero-PCIe-write m1n1 binary from the completed one-run test.

## Why this test exists

The first corrected run proved UART TX with BIT(2), but it depended on UART RX
to request `/proc/interrupts`. When both host commands went unanswered, it
could not distinguish these cases:

- AIC input 360 never asserted;
- the hard IRQ ran but did not classify RX BIT(1) as pending;
- the threaded handler ran but the byte did not reach the tty client;
- the storm guard disabled the line before the shell could answer.

This initramfs reports evidence over the working TX direction on a fixed
schedule. It does not start a ttydc shell and does not depend on receiving a
command before it prints the result.

## Exact artifacts

- proven zero-PCIe-write m1n1 control: SHA-256
  `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`
- storm-bounded `Image-dcuart-irq`: SHA-256
  `de09f5a17229e97d7cb291fe1471e63d2925ef3e8057d5019e4d380c5509cdf6`
- `t6040-j614s-dcuart-irq.dtb`: SHA-256
  `676be63aa9b7f059fbef0bfb79a93bb5b49d554a42b3e7cd2b9ee9844fa906ab`
- `initramfs-dcuart-irq-report.cpio.gz`: SHA-256
  `1376adda8d7379eb8a61d19664369515d28da304a13a30ee365061287874c337`
- embedded init source: `scripts/t6040-init-dcuart-irq-report`, SHA-256
  `a8a40375e89737f079182838aa317e236a5859ae8e3e8a16f2670269726c9839`

The extracted `/init` hash was verified equal to the source hash. Rebuild with
`scripts/t6040-build-dcuart-irq-report.sh`.

## Measurement sequence

The kernel performs the same reviewed UART startup writes as the completed
test: RX threshold 1, W1C RX BIT(1), then enable RX BIT(1). TX may temporarily
enable BIT(2). The 4,096-entry storm guard remains active and masks the UART
IRQ block on entry 4,097. There are no new addresses or kernel MMIO operations.

Userspace opens `/dev/ttydc0`, emits the instructions, and then waits five
seconds for those TX completions to settle. It saves a baseline copy of
`/proc/interrupts`, emits no UART output for ten seconds, and saves a second
copy. During that silent interval the host sends exactly one bounded line:

```text
IRQ_BIT1_PROBE
```

A background read may consume that one line, but stores its result only in
RAM until after the second snapshot. Because the diagnostic emits no UART TX
during the interval, a DockChannel interrupt-count delta cannot be caused by
the reporter's own TX traffic. After the interval it transmits both matching
interrupt lines, whether the RX read completed, and the bounded DockChannel
dmesg tail.

If output stops after the instruction banner, recover immediately and do not
retry the same image. If the full report prints, capture it and recover after
the result. No PCIe or NVMe node is present, and no storage namespace is
accessed.

## Approval gate

This is a new live run even though its kernel writes are unchanged. It requires
fresh explicit approval for one boot of the exact hashes above and one host
injection of the exact probe line during the ten-second silent window. No live
run has occurred yet.
