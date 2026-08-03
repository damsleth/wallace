# T6040 Alpine keyboard-control boot preflight

Date: 2026-07-23  
Status: static preflight; **do not run without a rig ticket and CJ approval**

## Purpose

Ticket 067 proved that the Alpine RAM-root boots and stays responsive, but its
7.1.3 USB-host kernel failed before registering any input device. This control
changes only the kernel/DT pair to the previously hardware-proven 7.2-rc2
internal-keyboard path. It tests whether the built-in keyboard can operate
Alpine's framebuffer-console shell.

The old kernel has no DockChannel TTY driver, so this is deliberately a
screen-and-keyboard test. The operator must be in front of the M4. DebugUSB is
used only for chainload and later recovery.

## Exact artifacts

| Artifact | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-keyboard` | `cc2b3de15efbf4fbf5c4d7ac7d6b8155e5c4c52e0deabd9e012ffa379b37fb58` |
| `t6040-j614s-kbd.dtb` | `2c23495973edb37f07cc7abab2377578a1f57837ca9f93fc5ae15b8a70961577` |
| `initramfs-alpine-ramroot.cpio.gz` | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |
| extracted embedded kernel config | `fb6b057529b9a1fffa4e032b52c71bf205716b2fcbb578aaf94d076567f8565c` |

The kernel is `7.2.0-rc2-gef5e754365e8-dirty`. Hash
`cc2b3de15...` is the ticket-011/2026-07-11 boot-test-4 artifact on which the
maintainer typed successfully with the built-in keyboard. It contains the old
ASC `MTPDBG` logging strings; this is not the separately blacklisted
`Image-keyboard-debug` (`b30a1cc6...`). The pinned image itself is already
hardware-proven.

## Static safety audit

- The extracted config has `CONFIG_INPUT`, `CONFIG_INPUT_EVDEV`, `CONFIG_HID`,
  `CONFIG_HID_GENERIC`, `CONFIG_HID_APPLE`, and
  `CONFIG_APPLE_DOCKCHANNEL_HID` built in.
- `CONFIG_ARM64_SME` is disabled. The Apple watchdog is built in.
- Apple NVMe and SART are modules. The Alpine initramfs contains and loads no
  kernel modules.
- DT decompilation shows the intended MTP ASC mailbox, MTP DART, DockChannel
  mailbox, and HID node enabled. The keyboard and multi-touch children are
  present.
- All three DWC3 controllers and all six USB DART nodes are disabled. ANS,
  SART, and internal NVMe are disabled. There is no force-host property and no
  enabled SPMI controller.
- Relative to the live-proven standard ticket-067 DT, the keyboard DT removes
  the DockChannel-UART mailbox/serial node and its per-instance mask
  properties. The SoC/MTP path is otherwise the same.
- The initramfs `/init` is byte-identical to
  `scripts/t6040-init-alpine-ramroot` at SHA-256
  `1ba4eaf9fa1654fe52ba1f11ae00377136284a46644ebd1fd9199e87f0fc9fff`.
  It mounts only proc, sysfs, devtmpfs, and tmpfs, performs no block discovery
  or module loading, and ends in an interactive `/dev/console` shell. Because
  `/dev/ttydc0` is absent, it waits up to 15 seconds before presenting the
  framebuffer shell.

No new MMIO path is introduced. This recombines a live-proven m1n1, a
live-proven keyboard kernel, the current minimal keyboard DT, and the
ticket-067-proven RAM-root.

## Proposed one-shot run

Keep the right-side USB stick disconnected and KIS on left-back. Boot with:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init
```

There is no `root=` argument. After the framebuffer prompt appears, the
maintainer types:

```sh
echo ALPINE_KBD_OK
cat /etc/alpine-release
apk --print-arch
cat /proc/partitions
```

Pass:

- keystrokes echo and execute;
- `ALPINE_KBD_OK`, `3.24.0`, and `aarch64` appear;
- `/proc/partitions` has no device rows;
- the shell remains responsive for at least ten seconds.

Stop on any SError, reset, DART fault, storage/USB probe, missing input, or lost
display. After the operator reports the result, use the approved DebugUSB
recovery procedure and verify a stable `Running proxy...`.

## Independent cross-review

`usb_smoke_cross_review` returned **PASS**, conditional on the documented
lease/CJ approval, physical presence, disconnected USB stick, exact
`maxcpus=1 idle=nop` arguments, and one-shot stop conditions.

The review independently confirmed the exact hashes and enabled-node set. It
also confirmed that PMGR labels containing `ans`, `atc`, or `spmi` are only
power-domain labels, not enabled controller nodes; the stale UART IRQ is absent
from the keyboard DT; the old image's `MTPDBG` strings do not make it the
blacklisted debug artifact; and missing `CONFIG_FONT_TER16X32` merely makes
fbcon select its compiled default font. There is no safety blocker to the
control boot.
