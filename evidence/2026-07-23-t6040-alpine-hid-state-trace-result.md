# T6040 Alpine HID state-trace result

Date: 2026-07-23  
Rig ticket: 074  
Result: **FAIL — Alpine TX reached, ttydc0 RX non-responsive; trace not captured**

## Exact inputs

| Input | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-hid-state-trace` | `e7138c03c5dcea63048adcc5b800781a73a544699e6b575cb7343bc3f4cf4576` |
| `t6040-j614s-dcuart-hid-state-trace.dtb` | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| `initramfs-alpine-ramroot.cpio.gz` | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |
| embedded/config file | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

The boot used the reviewed single-core arguments and no `root=`:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init
```

## Host setup

Two initial helper invocations failed before opening the proxy because the
short-lived command runner reaped `kisd` and left `/tmp/m1n1` dangling.
`chainload.py` returned `ENOENT`; neither attempt sent m1n1, the kernel, DTB, or
initramfs and neither counts as a target boot.

The documented persistent process-group anchor then kept `kisd` alive. A fresh
recovery reached a quiescent `Running proxy...`, the exact artifacts were
uploaded, and Linux handed off once.

## Result

DockChannel output reached the host and Alpine started:

```text
*** Alpine RAM-root ready on /dev/ttydc0 ***
No USB or internal storage is mounted.
Linux wallace-ramroot 7.1.3-g96ac043df12f-dirty #2 SMP PREEMPT ... aarch64 Linux
Alpine 3.24.0 (aarch64)
[ramroot] spawning Alpine root shell
wallace-ramroot:~#
```

The prompt emitted a terminal cursor-position query, but ttydc0 RX did not
respond. The first approved command was tried with LF and CR, and once after
the standard terminal `ESC[1;1R` response. None produced an echo or output.
During these attempts:

- `kisd` remained alive and attached;
- `/tmp/m1n1` resolved to the current raw PTY;
- a persistent foreground reader remained active;
- DockChannel TX had already delivered the complete Alpine banner and prompt.

This met the pre-registered non-responsive/lost DockChannel stop. No further
target diagnostic, module load, mount, network setup, probe, or retry boot was
performed. Because the shell could not receive commands, the `HIDTRACE`,
`dc_trace`, `hid_trace`, input inventory, and `/proc/partitions` checks were
not captured. The run therefore does not locate the HID failure boundary and
does not validate or invalidate the trace counters.

The instrumentation is deliberately observation-only but not timing-neutral.
Its added UART poll counter is a plausible perturbation to record, not evidence
that it caused the missing RX.

## Recovery and evidence

The run stopped at the RX failure. DebugUSB recovery returned the M4 to a
quiescent `Running proxy...`; no async SError, DART fault, or watchdog/reset
loop was observed before recovery.

| Evidence | Bytes | SHA-256 |
|---|---:|---|
| `logs/t6040-linux-20260723-hid-state-trace.log` | 465 | `6f42f4db69cd6b3e70ce91729fd3ccce488fd11dffa15f29dfa906f45401aa62` |
| `linux-build-out/dcuart-boot.log` | 25,483 | `09ad8d1b23d1fbb79cdba7e78cf75f236bca32ffe8f5ba5bcb285c4ab090e3d2` |
| `linux-build-out/dcuart-chainload.log` | 4,726 | `a77bed1f997d01eac6027650e34453bfba047fdd3e5690d5af3eec655ac121b8` |

Next: do not repeat ticket 074 unchanged. Build an offline, bootarg-gated
initramfs reporter that automatically prints only the already-approved bounded
trace/input/partition inventory over working ttydc0 TX, requiring no inbound
shell command. Cross-review and hash that new artifact before proposing one
replacement rig run.
