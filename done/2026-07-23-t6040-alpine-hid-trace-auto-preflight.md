# T6040 Alpine HID automatic trace-capture preflight

Date: 2026-07-23  
Offline ticket: 075  
Proposed rig ticket: 076  
State: **reviewed proposal; maintainer approval required**

## Purpose

Ticket 074 reached Alpine over ttydc0 TX, but ttydc0 RX would not accept the
first approved command. This one-shot replacement changes only the initramfs.
The exact observation kernel and storage-disabled DT remain unchanged. The
exact command-line token `t6040.hid_trace_auto=1` makes `/init` emit the
already-approved bounded trace/input/partition report over ttydc0 TX before it
starts the shell, so the run sends no target input.

## Exact inputs

| Input | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-hid-state-trace` | `e7138c03c5dcea63048adcc5b800781a73a544699e6b575cb7343bc3f4cf4576` |
| `t6040-j614s-dcuart-hid-state-trace.dtb` | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| `initramfs-alpine-hid-trace-auto.cpio.gz` | `d5b790c63276816a3d69071797da459918717924885174d2a8b84225c6b24093` |
| embedded/config file | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

The m1n1, Image, DTB, and config byte-match ticket 074. Only the initramfs
changes. Its source, reproducible build, host tests, archive checks, and
independent review are recorded in
`done/2026-07-23-t6040-alpine-hid-trace-auto-reporter.md`.

Independent reviewer `usb_smoke_cross_review` returned **PASS** for the final
`d5b790c6...` archive and left the rig untouched. The archive has 518
root-owned entries, no block/character nodes or kernel modules, and embedded
init/reporter scripts byte-identical to the reviewed sources.

The same reviewer separately verified this ticket's exact hashes, environment
expansion, no-`root=` command line, TX-only/no-target-input procedure,
storage-disabled DT, pass/stop conditions, one-run/no-retry rule, and explicit
approval gate. Result: **PASS**; the rig remained untouched. The persistent
PTY/process-group anchor is mandatory because ticket 074 showed that
short-lived automation can reap `kisd`.

The DT still enables MTP HID on AIC input 776 and DockChannel UART in poll mode
with inert input 816, while every USB/DART/ANS/SART/NVMe node remains disabled.
The kernel trace is observation-only and carries no receive kick, retry, new
MMIO, or control-flow change.

## Proposed one-shot procedure

Before acquiring the lease, ensure the bus-powered USB stick is disconnected
from the M4, keep the proven DebugUSB/KIS tether on left-back, and leave the
other ports empty. Use the documented persistent process-group/terminal
discipline so `kisd` and the foreground reader remain anchored throughout.

After explicit maintainer approval:

```sh
scripts/rig-lease.sh acquire codex \
    "ticket 076 Alpine HID automatic trace capture" 1394c345
RIG_AGENT=codex bash scripts/t6040-debugusb-console.sh reboot
RIG_AGENT=codex \
M1N1_BIN=/Users/damsleth/Code/linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin \
M1N1DEVICE=/tmp/m1n1 IMAGE=Image-hid-state-trace BOOT_WAIT=45 \
EXTRA_BOOTARGS=t6040.hid_trace_auto=1 \
KERNEL_LOG_ARGS=ignore_loglevel \
bash scripts/t6040-boot-dcuart.sh \
    t6040-j614s-dcuart-hid-state-trace.dtb \
    initramfs-alpine-hid-trace-auto.cpio.gz
```

Exact boot arguments:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel t6040.hid_trace_auto=1 rdinit=/init
```

There is no `root=`.

Do not write anything to `/tmp/m1n1` after handoff. Capture output only from:

```text
===== T6040 HID TRACE AUTO REPORT BEGIN =====
```

through:

```text
===== T6040 HID TRACE AUTO REPORT END =====
```

Then stop and recover a stable `Running proxy...`; the later interactive shell
is outside this experiment.

## Pass and stop conditions

Pass requires both report markers, release/architecture, bounded `HIDTRACE`
output, every expected readable `dc_trace`/`hid_trace` record, input inventory,
and a partition inventory with no unexpected block device. HID creation or
absence is an observed branch, not permission for follow-up commands.

Stop immediately on async SError, reset/watchdog loop, DART fault, any
USB/ANS/NVMe probe, unexpected block device, lost DockChannel TX, a missing
report marker, or missing trace attributes. Do not retry in the same lease.
Do not send shell input, load modules, mount anything beyond the initramfs's
existing pseudo-filesystems, configure networking, install packages, or probe
devices.

No outcome authorizes an unreviewed receive kick, retry, or new MMIO access.
