# T6040 Alpine HID RX re-arm preflight

Date: 2026-07-23  
Rig ticket: 071  
State: **completed — FAIL; see
`done/2026-07-23-t6040-alpine-hid-rx-rearm-result.md`**

This is one storage-disabled boot of the current 7.1.3 Alpine kernel with the
single DockChannel RX mask/drain/re-arm correction from offline ticket 069.

Independent reviewer `usb_smoke_cross_review` verified the exact exported and
build-tree artifacts, embedded config, decompiled DT, patch, harness, command,
bootargs, and stop/recovery rules and returned **PASS**. No rig was touched.
The run was subsequently approved and executed once.

## Physical state

- Disconnect the bus-powered USB-C memory stick from the M4's right port.
- Keep the proven DebugUSB/KIS tether on left-back.
- Leave left-front and right empty.

## Exact inputs

| Input | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-hid-rx-rearm` | `a6c2f09354bf1d61559b450f9430eb06d42f94d027d539c2deade708d708c4ff` |
| `t6040-j614s-dcuart-hid-rx-rearm.dtb` | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| `initramfs-alpine-ramroot.cpio.gz` | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |
| embedded/config file | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

The embedded config matches ticket 067 byte-for-byte. The DT enables only the
known MTP HID path and poll-mode DockChannel UART; external USB, USB DARTs,
ANS, SART, and NVMe remain disabled. UART now carries the corrected but inert
poll-mode IRQ 816. The kernel patch only masks, acknowledges, drains, and
re-arms the already described MTP DockChannel RX interrupt.

## Exact run

After CJ approval and explicit selection of 071 as the next runnable rig
experiment:

```sh
scripts/rig-lease.sh acquire codex "ticket 071 Alpine HID RX re-arm" 1394c345
RIG_AGENT=codex bash scripts/t6040-debugusb-console.sh reboot
RIG_AGENT=codex \
M1N1_BIN=/Users/damsleth/Code/linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin \
M1N1DEVICE=/tmp/m1n1 IMAGE=Image-hid-rx-rearm BOOT_WAIT=45 \
EXTRA_BOOTARGS= KERNEL_LOG_ARGS=ignore_loglevel \
bash scripts/t6040-boot-dcuart.sh \
    t6040-j614s-dcuart-hid-rx-rearm.dtb \
    initramfs-alpine-ramroot.cpio.gz
```

Exact boot arguments:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init
```

There is no `root=`.

## Pass and checks

On `/dev/ttydc0`, run only:

```sh
cat /etc/alpine-release
apk --print-arch
cat /proc/bus/input/devices
ls -l /dev/input
cat /proc/partitions
```

Pass requires:

- Alpine `3.24.0`, `aarch64`, and a responsive DockChannel shell;
- Apple `05ac:0359` input identity and registered keyboard/input event device;
- the operator can type `echo ALPINE_KBD_OK` at the framebuffer shell and see
  `ALPINE_KBD_OK`;
- `/proc/partitions` has no block devices;
- the remote shell remains responsive for at least ten seconds.

Do not load modules, mount anything, configure networking, invoke `apk add`, or
probe devices. Stop immediately on async SError, reset/watchdog loop, DART
fault, any USB/ANS/NVMe probe, unexpected block device, lost DockChannel, or
missing input registration. Recover a stable `Running proxy...` before
releasing the lease.
