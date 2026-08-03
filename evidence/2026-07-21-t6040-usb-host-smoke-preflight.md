# T6040 USB2-host smoke preflight (2026-07-21)

Pre-approval packet for the first live USB2-host enumeration test. This is a
SMOKE boot only: it passes no `root=`, mounts no block device, and stops in the
initramfs diagnostic shell after reporting USB and block enumeration.

## Exact live inputs

| Input | SHA-256 |
|---|---|
| `linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `linux-build-out/Image-usb-host` | `6f0daf57baf942d6e1f43d8efa2ebd4160e976c02ccfaad232dd42e918eb7482` |
| `linux-build-out/t6040-j614s-dcuart-usb-host-left-front.dtb` | `6e6f6bfa4eee896211516ac04e242f96fc650410900b8641fc5bcee443a2d430` |
| `linux-build-out/t6040-j614s-dcuart-usb-host-right.dtb` | `9bee944b8bb0d6d7ab541962ea2edc9a57c4069fedcd6c32db21e3b824a43759` |
| `linux-build-out/initramfs-usb-root.cpio.gz` | `8b9b80c4eaad07aa0efa578a827f9d0766be81e9a4aed2650e748b1fc65993c8` |
| `linux-build-out/config-usb-host` | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

The left-front and right manifests in `linux-build-out/` each verify their six
eligible files with `shasum -a 256 -c`. The old all-port DTB remains archived
but is not eligible for a live boot.

The pinned m1n1 binary is the already live-proven zero-PCIe-write upper-guard
control from m1n1 commit `eed11760`, not the currently rebuilt `main` binary.
Kernel source is `96ac043df12fd3b8648505c51933b1552d033c4c`; its applied build-tree binary
diff hashes to
`e2e6e5b3e0f700a6497446da2b4679290a78a98351ed4ea0dde3a380b738b5ed`.

## Static safety review surface

- Each eligible DT enables only one ADT-derived DWC3 wrapper, its two
  ADT-derived DART instances, and its existing PMGR power-domain reference.
  Exact register/IRQ/IOMMU mappings are recorded in
  `done/2026-07-14-t6040-usb-host-dt-audit.md`.
- No ATC PHY node or unknown tunable bucket is enabled. No blind MMIO probing is
  present. The driver patch only invokes the existing host initializer at probe.
- The ANS mailbox, SART, and internal NVMe DT nodes remain `status = "disabled"`.
  NVMe is modular in the config and cannot probe without an enabled DT node.
- No SPMI, PMU, charger, or NVRAM access is introduced. The only new live path
  is the audited USB/DART/power-domain path represented by the DT.
- Both DTBs carry measured DockChannel-UART AIC input 816 instead of the ADT's
  false 360. The node retains `apple,poll-mode`, so the smoke test still does
  not request or exercise the interrupt.
- The initramfs has no `root=` in this run. Its smoke branch only reads sysfs,
  `/proc/partitions`, and `dmesg`, then starts a shell. It never invokes
  `mount` for any block device.
- The captured ADT maps `usb-drd0/1/2` to
  `left-back/left-front/right`. DebugUSB is proven on left-back, so both
  eligible variants leave `usb-drd0`, its DARTs, and the unused host candidate
  disabled. VBUS is not manipulated; the drive should preferably be behind a
  powered hub or self-powered enclosure.
- Boot remains `maxcpus=1 idle=nop`. The live machine proved 14 cores
  (4E + 5P + 5P); the candidate DTB describes the extra `cpu@10105` but marks it
  disabled, so the enabled topology is correct. Ticket 034 still exists to
  validate Linux secondary-core boot. Raising `maxcpus` now would combine that
  untested SMP step with USB enumeration for no benefit to this smoke test.

## Exact proposed run

After a second-agent review and CJ approval of the resulting rig ticket:

```sh
scripts/rig-lease.sh acquire codex "USB2 host smoke, no root mount" 1394c345
RIG_AGENT=codex bash scripts/t6040-debugusb-console.sh reboot
USB_HOST_DTB=t6040-j614s-dcuart-usb-host-right.dtb
RIG_AGENT=codex \
M1N1_BIN=/Users/damsleth/Code/linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin \
M1N1DEVICE=/tmp/m1n1 IMAGE=Image-usb-host BOOT_WAIT=45 \
EXTRA_BOOTARGS= KERNEL_LOG_ARGS=ignore_loglevel \
bash scripts/t6040-boot-dcuart.sh \
    "$USB_HOST_DTB" initramfs-usb-root.cpio.gz
```

The boot harness generates exactly:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init
```

## Pass/stop conditions

Pass: one external USB device enumerates, an `sd*` device remains present for at
least 10 seconds, and the DockChannel shell remains responsive. Record the
physical port, xHCI/DWC3/DART messages, VID:PID/product, and partition list.

Stop immediately on an async SError, watchdog reset, DART fault, loss of
DockChannel, repeated controller reset, or any sign that internal NVMe probed.
Do not add `root=`, mount the disk, change ports, or change IRQs in the same
approved experiment. Restore `Running proxy`, then release the lease healthy;
if recovery is uncertain, release it wedged.

Review status: **PASS for both port-specific sets, conditional on selecting and
pinning exactly one before CJ approval.** The focused independent review
verified the decompiled DTBs, both six-file manifests, raw ADT mapping,
initramfs behavior, and disabled NVMe/SART/unused-USB paths. Full result:
`done/2026-07-21-t6040-usb-host-smoke-crossreview.md`.

**Selected 2026-07-21:** the external drive is attached to the right-side port,
so only the right/`usb-drd2` DTB above is eligible. Rig ticket 063 pins that
exact set and is awaiting CJ approval.
