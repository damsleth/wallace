# T6040 Alpine RAM-root boot preflight (2026-07-23)

Pre-approval packet for rig ticket 067. This is a single storage-free distro
boot. It introduces a new userspace archive but no kernel, DT, m1n1, bootloader,
MMIO, power-domain, or firmware behavior.

## Physical state

- Disconnect the bus-powered USB-C memory stick from the M4's right port.
- Keep the proven DebugUSB/KIS tether on left-back.
- Leave left-front and right empty. No powered hub or external storage is
  required.

## Exact inputs

| Input | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-usb-host` | `6f0daf57baf942d6e1f43d8efa2ebd4160e976c02ccfaad232dd42e918eb7482` |
| `t6040-j614s-dcuart.dtb` | `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814` |
| `initramfs-alpine-ramroot.cpio.gz` | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |
| `config-usb-host` | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

The m1n1 and kernel booted successfully in ticket 063. The standard DTB was
previously reviewed and boot-proven; fresh decompilation confirms:

- all three USB DWC3 controllers and all USB DARTs are `status = "disabled"`;
- ANS, SART, and internal NVMe are `status = "disabled"`;
- there is no enabled SPMI or ATC PHY path and no `apple,force-host-mode`;
- DockChannel uses `apple,poll-mode`. Post-run re-decompilation found that this
  exact pinned standard DTB still encodes the stale ADT IRQ 360, despite the
  source and port-specific DTBs having been corrected to 816. Poll mode bypasses
  IRQ acquisition entirely, so the stale cell was not exercised and does not
  affect this run. Do not reuse this DTB for any interrupt-mode experiment.

The new initramfs is host-validated and reproducible as recorded in
`done/2026-07-23-t6040-alpine-ramroot-artifact.md`.

## Exact run

After CJ approval:

```sh
scripts/rig-lease.sh acquire codex "ticket 067 Alpine RAM-root boot" 1394c345
RIG_AGENT=codex bash scripts/t6040-debugusb-console.sh reboot
RIG_AGENT=codex \
M1N1_BIN=/Users/damsleth/Code/linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin \
M1N1DEVICE=/tmp/m1n1 IMAGE=Image-usb-host BOOT_WAIT=45 \
EXTRA_BOOTARGS= KERNEL_LOG_ARGS=ignore_loglevel \
bash scripts/t6040-boot-dcuart.sh \
    t6040-j614s-dcuart.dtb initramfs-alpine-ramroot.cpio.gz
```

Exact boot arguments:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init
```

There is no `root=`. The archive is uploaded into RAM by m1n1 and becomes the
kernel rootfs.

## Pass and read-only checks

Pass only if DockChannel remains responsive and reports Alpine 3.24.0/aarch64.
After the banner, send:

```sh
cat /etc/alpine-release
apk --print-arch
mount
cat /proc/partitions
echo RAMROOT_OK >/tmp/ramroot-probe
cat /tmp/ramroot-probe
```

Expected:

- `3.24.0`, `aarch64`, and `RAMROOT_OK`;
- mounted filesystems are only rootfs plus proc/sysfs/devtmpfs/tmpfs;
- no `sd*` or `nvme*` block device is present;
- the shell stays responsive for at least ten seconds.

The `/tmp` write is explicitly RAM-only and disappears on reboot. Do not invoke
`apk add`, configure networking, load modules, probe devices, or mount anything
in this first run.

Stop immediately on async SError, reset/watchdog loop, DART fault, lost
DockChannel, any USB/ANS/NVMe probe, or unexpected block device. Restore a fresh
`Running proxy` before releasing the lease.
