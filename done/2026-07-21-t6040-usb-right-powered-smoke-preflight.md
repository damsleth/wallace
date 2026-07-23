# T6040 right-port powered USB2 smoke preflight (2026-07-21)

Pre-approval packet for rig ticket 065. Ticket 063 used a simple, directly
attached, bus-powered USB-C memory stick. Its root-hubs-only result therefore
did not rule out absent downstream VBUS or direct C-to-C role negotiation.

This is a topology-only retry. Kernel, DT, initramfs, m1n1, boot arguments,
port selection, and safety boundaries are unchanged.

## Hardware prerequisite

Do not approve or run ticket 065 until all of the following are true:

- A standards-compliant externally powered USB hub or genuinely self-powered
  USB2 mass-storage enclosure is available. Do not use a passive hub or an
  adapter marketed only for charging.
- For the preferred hub topology, connect the hub's upstream data port to the
  M4's right-side port and attach a simple known-good USB2 mass-storage device
  downstream. A USB-A flash drive is ideal; a USB-C stick is acceptable only
  on a downstream USB-C **data** port.
- Validate the powered hub and storage device on the M1/macOS host first, then
  eject it cleanly. This changes only the external test fixture, not the M4.
- Power the hub and connect the complete topology before the M4 power cycle.
  Do not hotplug, flip cables, change downstream devices, or move ports during
  the bounded run.
- Keep DebugUSB/KIS on left-back. Linux enables only right/`usb-drd2`; left-back
  and left-front remain disabled.

The hub must not rely on or intentionally backfeed its upstream port for power.

## Exact unchanged live inputs

| Input | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-usb-host` | `6f0daf57baf942d6e1f43d8efa2ebd4160e976c02ccfaad232dd42e918eb7482` |
| `t6040-j614s-dcuart-usb-host-right.dtb` | `9bee944b8bb0d6d7ab541962ea2edc9a57c4069fedcd6c32db21e3b824a43759` |
| `initramfs-usb-root.cpio.gz` | `8b9b80c4eaad07aa0efa578a827f9d0766be81e9a4aed2650e748b1fc65993c8` |
| `System.map-usb-host` | `019d7504716788f6bda8b22a6bdbef94b89a940128be4083ae3d2f1d491d9d47` |
| `config-usb-host` | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

These are the independently reviewed ticket-063 artifacts. No rebuild or new
artifact review is needed unless any hash changes. The exact boot arguments
remain:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init
```

There is no `root=`. The initramfs mounts only its pseudo-filesystems, reports
USB/block state twice ten seconds apart, and opens a diagnostic shell. It does
not mount or write the external storage or touch internal NVMe.

## Run and recovery

After CJ approves ticket 065 and the powered topology is already connected:

```sh
scripts/rig-lease.sh acquire codex "ticket 065 powered USB2 smoke, no root" 1394c345
RIG_AGENT=codex bash scripts/t6040-debugusb-console.sh reboot
RIG_AGENT=codex \
M1N1_BIN=/Users/damsleth/Code/linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin \
M1N1DEVICE=/tmp/m1n1 IMAGE=Image-usb-host BOOT_WAIT=45 \
EXTRA_BOOTARGS= KERNEL_LOG_ARGS=ignore_loglevel \
bash scripts/t6040-boot-dcuart.sh \
    t6040-j614s-dcuart-usb-host-right.dtb \
    initramfs-usb-root.cpio.gz
```

Pass only if a non-root-hub USB child appears, an external `sd*` remains present
for at least ten seconds, and DockChannel stays responsive. Record VID:PID,
product, speed, partition list, and DWC3/xHCI/DART messages.

Stop immediately on async SError, reset/watchdog loop, DART fault, repeated
controller reset, lost DockChannel, or any internal NVMe probe. Recover to a
fresh `Running proxy` before releasing the lease.

If this powered topology still reports only root hubs, do not retry it or vary
the topology under the same approval. Close the live USB path pending reviewed
T6040 HPM/SPMI and ATC PHY support.
