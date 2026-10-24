# T6040 / J614s device-tree sources and checklist

Current as of 2026-08-03. The early bring-up checklist is complete enough to
boot and exercise the board; this page now records what is verified and what
still needs upstream-quality cleanup.

## Verified

- Mac16,8 / J614s model and T6040 compatibility.
- 14-core topology: 4 E cores and two 5-core P clusters.
- AIC and measured DockChannel UART interrupt input 816.
- PMGR topology and the power domains used by current drivers.
- watchdog and simple framebuffer handoff.
- DockChannel UART and HID transport.
- SMC mailbox/SRAM, battery/AC/hwmon children, and approved PCIe endpoint-power
  GPIOs.
- PCIe root complex, port layout, DART mappings, BCM4388 WiFi/Bluetooth, and
  GL9755 SD reader.
- cpufreq nodes and OPPs.
- experimental T8132-style ANS/NVMe split mappings from the captured J614s ADT.
- SDHCI and exFAT path through `mmc0`.

This directory contains the active board sources; the Linux worktree carries
their build-tree counterparts. The build copies DT files into a clean committed
kernel tree; uncommitted kernel code is not part of the build.

## Still open

| Area | Required evidence |
|---|---|
| MM/SMP | Explain the copy-on-write fault before claiming stable 14-core userspace |
| cpuidle/suspend | T6040 retention and locked-sysreg contract |
| panel backlight | Correct DCP/DWI ownership and bindings |
| keyboard backlight | Working through `fpwm0` and `pwm-leds`; keep regression coverage |
| trackpad | v2 power request and touch/haptics proven (230); daily integration (301) and upstream comparison (6002) |
| USB host | Reversible HPM role/VBUS plus ATC/eUSB2/xHCI sequence |
| NVMe | Fix the Linux first-I/O-CQ-wrap firmware assert |
| GPU | Explicit G16-compatible kernel, firmware ABI, m1n1, and Mesa support |
| audio/camera | ADT-backed nodes and upstream driver support |

## Validation for every DT change

1. Derive addresses, interrupts, power domains, and IOMMU IDs from the captured
   J614s ADT or a cited upstream binding; do not copy another SoC blindly.
2. Build the exact board DTB from a clean kernel tree.
3. Run `dtc`, `dtbs_check`, and a decompile review.
4. Compare the final DTB, not only the source diff.
5. Pin the DTB SHA-256 in any live ticket.
6. Confirm that unrelated experimental nodes remain disabled.
7. Stop before a live run if a schema warning masks an address, interrupt,
   IOMMU, power, or reset uncertainty.

## Historical source

The original 2026-07-10 extraction commands and placeholder audit are retained
in Git history. Current ADT-derived results are documented in `evidence/`,
especially the Linux DT series, PCIe endpoint-power, SD preflight, and NVMe
port write-ups.

## October upstream comparison (ticket 6002 complete)

The [pinned property/patch map](../evidence/2026-10-24-upstream-convergence-audit.md)
reparsed both saved live J614s ADTs and compared the minimal submitted and
fuller Yuka component DTs. Keep local DTs for LC1 source assembly (6004):

- MacBook disp0 + dispext0/1; delete dispext2 only at the correct board scope,
  while keeping the local firmware-owned display-CPU policy.
- Proven NVMe reg9 64 KiB + reg3 NVMMU split; Yuka's single 384 KiB reg9
  window and 64 KiB SART window conflict with the captured/proven local sizes.
- Proven SD port01/DART1; Yuka's port02/DART2 node is a separate migration.
- Mailbox-based HID, SID0 DMA ownership and nine-byte v2 power request;
  the old-helper DT's SRAM/SID1/FIFO topology is a different driver contract.
- Measured DockChannel UART IRQ 816, even though the saved ADT says 360.

AP GPIO no-restore metadata decodes to pins 191/192/190; it does not by itself
prove forbidden access or equivalent `gpio-reserved-ranges` semantics. Do not
copy other SoCs' reserved-pin lists. Standardize properties only with the
matching driver/binding review. Neither source assembly nor this comparison
passes schema or hardware gates; the validation rules above remain mandatory.
