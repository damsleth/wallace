# T6040 ticket 073 DockChannel IRQ-816 cross-review (2026-07-24)

Reviewer: Sol. Result: **PASS for one bounded boot**.

The four ticket hashes were recomputed and match:

- m1n1 `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`
- Image `a6c2f09354bf1d61559b450f9430eb06d42f94d027d539c2deade708d708c4ff`
- DTB `21a3446830a50a0d739a6e55e2ef9f9ee3986bcc677d12e5caceced708cf22a2`
- initramfs `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`

Decompiling the base and candidate DTBs shows only the intended model string
and DockChannel mailbox changes: AIC input `360` becomes measured input `816`
(`0x330`, level-high) and `apple,poll-mode` is removed. The known UART masks
remain RX `BIT(1)` and TX `BIT(2)`; the irq/config/data register tuple is
unchanged. The kernel includes the previously reviewed configurable-mask and
RX mask/ack/drain/re-arm path.

The extracted initramfs mounts only proc/sysfs/devtmpfs, services the watchdog,
waits for `ttydc0`, and provides the existing shell. It contains no storage or
USB action. The m1n1 object is the PCIe-write-free upper-guard build.

One boot may therefore test only whether host input reaches the shell through
AIC input 816 without an interrupt storm. Poll mode remains the immediate
fallback. Stop and recover on absent output/input, watchdog/reset, SError, or
runaway IRQ behavior.
