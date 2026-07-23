# T6040 DockChannel-UART TX-only IRQ counter diagnostic

> **Superseded routing note (2026-07-21):** this historical image used ADT
> input 360. Bounded M4 Pro measurement later found the real UART interrupt at
> AIC input 816. The observations below remain valid, but they did not test the
> UART's AIC route. See `done/2026-07-21-asahi-dev-log-review.md`.

Prepared and run once on 2026-07-14 after the corrected RX BIT(1) interactive
run remained silent. The unique instruction banner printed and the host sent
the exact approved probe line in the silent window, but no post-window report
appeared. This follow-up changed only the initramfs behavior: it reused the
exact storm-bounded kernel, DTB, and zero-PCIe-write m1n1 binary from the first
corrected run.

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

The maintainer approved one boot of the exact hashes above and one exact probe
line. That run is complete. Any revised image or retry requires a new exact
review and approval.

## Live result

The diagnostic printed all five instruction lines. Six seconds after the final
line appeared, the host injected exactly `IRQ_BIT1_PROBE\n`. No subsequent UART
output appeared during 35 seconds of capture: neither the measurement-complete
line nor either interrupt snapshot was transmitted. The log remained 544
bytes. Following the gate, the image was not retried; a sanctioned DebugUSB
reboot restored a fresh m1n1 proxy. No PCIe, NVMe, or storage access occurred.

Transcript:
`logs/t6040-console-20260714-dockchannel-irq-tx-report.log`, SHA-256
`b6ca4474b017035e5b0335f955abb8dd98097a1af4864fb90e185cf084db9ad2`.

The embedded BusyBox was separately tested on an arm64 pseudo-terminal: its
background `read -t` expired in the requested two seconds with status 1. The
same init script also passed BusyBox `sh -n`. A userspace timeout hang is
therefore not a credible explanation for 35 seconds of silence.

The timing strongly suggests that enabling or exercising RX BIT(1) stalls the
shared interrupt-driven mailbox completion path—most plausibly by tripping the
4,096-entry guard and disabling the shared IRQ—but the guard message could not
be relayed after TX completion stopped, so this is still an inference. The next
diagnostic must make TX completion independent of the AIC line while leaving RX
interrupt-driven, then emit the guard message and counters over that polled TX
path. Do not retry this image unchanged.
