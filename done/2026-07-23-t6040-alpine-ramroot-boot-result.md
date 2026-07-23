# T6040 Alpine RAM-root boot result

Date: 2026-07-23  
Rig ticket: 067  
Result: **RAM-root PASS; internal keyboard regression found**

## Exact artifacts

| Artifact | SHA-256 |
|---|---|
| m1n1 | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-usb-host` | `6f0daf57baf942d6e1f43d8efa2ebd4160e976c02ccfaad232dd42e918eb7482` |
| `t6040-j614s-dcuart.dtb` | `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814` |
| `initramfs-alpine-ramroot.cpio.gz` | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |
| embedded kernel config | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

Boot arguments were:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init
```

There was no `root=` argument. The right-side USB stick was disconnected.
The pinned standard DTB has `apple,poll-mode`; a post-run re-decompilation
found its UART interrupt cell was a stale 360 rather than the corrected 816.
Poll mode never acquires that interrupt, so the stale cell was inert in this
run. The source and future DTBs remain corrected to 816.

## RAM-root result

The image booted to an interactive DockChannel shell:

```text
*** Alpine RAM-root ready on /dev/ttydc0 ***
No USB or internal storage is mounted.
Linux wallace-ramroot 7.1.3-g96ac043df12f-dirty ... aarch64
Alpine 3.24.0 (aarch64)
[ramroot] spawning Alpine root shell
wallace-ramroot:~#
```

The bounded checks passed:

- `/etc/alpine-release` reported `3.24.0`;
- `apk --print-arch` reported `aarch64`;
- rootfs was writable RAM, with only proc, sysfs, devtmpfs, `/run`, and `/tmp`
  mounted;
- `/proc/partitions` contained only its header and no block devices;
- a write/read round trip on `/tmp` returned `RAMROOT_OK`;
- the shell remained responsive beyond ten seconds;
- no `sd`, NVMe, ANS, xHCI, DWC3, SError, DART fault, or reset appeared.

This clears the storage-free distro/userspace milestone. Alpine and the
initramfs are not the reason the internal keyboard failed.

## Internal keyboard regression

The internal keyboard did **not** work and no Linux input device registered:

- `/dev/input` did not exist;
- `/proc/bus/input/devices` and `/sys/class/input` were empty;
- the embedded config has `CONFIG_INPUT=y`, `CONFIG_INPUT_EVDEV=y`,
  `CONFIG_HID=y`, `CONFIG_HID_GENERIC=y`, `CONFIG_HID_APPLE=y`, and
  `CONFIG_APPLE_DOCKCHANNEL_HID=y`;
- the DT contains enabled MTP DART, mailbox, HID, `keyboard`, and
  `multi-touch` nodes.

MTP itself booted and its firmware reported:

```text
IPD HIDSPI attached
Initializing comm interface <2- "keyboard">
Keyboard interface configuration completed
Keyboard ready
```

The AP-side transport then stopped short of the identity exchange:

```text
hid-generic 0019:0000:0000.0001: device has no listeners, quitting
```

The MTP DockChannel interrupt count reached 383 and remained unchanged over a
two-second sample. Its threaded IRQ task and relevant workers were idle, not
blocked. In the known-good 7.2-rc2 keyboard run, this stage continues by
obtaining the STM identity (`05ac:0359`) and registering:

```text
input0 = Apple DockChannel Multi-touch
input1 = Apple DockChannel Keyboard
```

Therefore this is a kernel/DockChannel receive-path regression in the
7.1.3-based `Image-usb-host`, not expected Alpine behavior and not a missing
userspace keymap or evdev configuration.

## Recovery and evidence

The M4 was remotely rebooted after the checks. DebugUSB reattached and m1n1
returned to a stable `Running proxy...` state with `kisd` alive.

Full live console:
`/Users/damsleth/Code/linux-build-out/dcuart-console.log`, 19,241 bytes,
SHA-256 `f2a9196b59c70ddd784e468d57b8434d57a7c21fbbebdee553f83ade5d97f4eb`.

Next: isolate the 7.2-rc2 known-good versus 7.1.3 USB-host DockChannel delta,
then build a storage-disabled Alpine candidate which retains both ttydc0 and
the proven keyboard registration path.
