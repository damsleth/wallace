# T6040 ticket 005 maxcpus=2 cross-review (2026-07-24)

Reviewer: Sol. Result: **PASS for one bounded boot**.

## Exact artifacts

| Input | SHA-256 | Review |
|---|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` | matches the PCIe-write-free, previously live-proven upper-guard object |
| `Image-dcuart-irq816` | `a6c2f09354bf1d61559b450f9430eb06d42f94d027d539c2deade708d708c4ff` | exact ticket manifest |
| `t6040-j614s-dcuart.dtb` | `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814` | exact ticket manifest |
| `initramfs-smp-report.cpio.gz` | `160cd9bdc8b75f10243124c1baea7ae0f4cd9e45b7284b948681e74edd8e90ea` | exact ticket manifest |

The initramfs was extracted and its `/init` is byte-identical to
`scripts/t6040-init-smp-report`. The DTB decompiles with the board-correct
four-E plus five-P plus five-P CPU nodes, the intentional disabled
`cpu@10105` placeholder, polling DockChannel console, and disabled ANS/SART,
NVMe, and USB-host nodes.

## Boundary

The only runtime change from the proven console boot is the final
`maxcpus=2` boot argument and the read-only reporter. `idle=nop` remains in
force. The reporter mounts only proc/sysfs/devtmpfs, services the watchdog,
prints CPU masks and `/proc/cpuinfo`, pins one trivial task to CPU 1, and
opens the existing polling console. It performs no MMIO, SPMI, PMU, storage,
USB, PCIe, or DT mutation.

Pass requires CPUs 0-1 online, two processors, CPU-1 task liveness, a stable
shell, and no watchdog reset. Stop on SError, reset, or a missing report.
