# 5020: 5019 onboard debug kernel booted (live checks, 2026-10-30)

**Status:** live checks PASS; the warm-reboot pstore check is still pending (it needs one clean reboot).

CJ enrolled `wallace-5019.build1.bin` in 1TR. All checks below ran on the M4, on that kernel.

## Identity

- `uname`: `7.1.3-g6d2e54a0df87-dirty #1 SMP PREEMPT 2026-10-30T11:07:38+01:00`. This is
  byte-identical to the `Linux version` string in `/mnt/sd/wallace-5019/Image`.
- `/mnt/sd/wallace-5019/SHA256SUMS`: all OK. Image `41f9fdc360b536a2…`, DTB `1a49d19dd3778799…`,
  object `28127903fb83ad4a…`, all equal to the 5019 evidence.
- cmdline: unchanged from 5014 (`maxcpus=1 idle=nop nokaslr … rdinit=/init`).

## Checks

| check | result |
|---|---|
| boot, OpenRC, desktop | OK |
| exFAT on this boot | clean (no "linux exFAT is dirty" line, no fsck) |
| `write_cache` | `write through` |
| `/dev/uhid`, `/dev/uinput` | present (T6040_BLE_HID) |
| BLE mouse | MX Ergo S bonded and connected: `input2 "MX Ergo S Mouse"` via `/devices/virtual/misc/uhid/0005:046D:B03E.0007`, works in X |
| ftrace | `function` tracer filtered to `apple_nvme_*`: 74 hits over a `sync` |
| kprobes | `p:wallace_probe do_sys_openat2`: 17 hits, probe removed afterwards |
| dynamic debug | 7677 call sites in `/proc/dynamic_debug/control` |
| IKHEADERS | `/sys/kernel/kheaders.tar.xz`, 4,680,464 B |
| ramoops | reserved-mem `0x10300000000..0x103001fffff` (2 MiB, nomap); "Registered ramoops as persistent store backend"; `ramoops-1` console enabled; pstore mounted |
| ramoops params | record 128 KiB, console 256 KiB, ftrace 256 KiB, **pmsg 0**, max_reason 2 (oops/panic) |

**Correction to the plan:** `pmsg_size=0`, so there is no `/dev/pmsg0` and the planned
`/dev/pmsg0` marker test cannot run. The warm-reboot check uses the console region instead: write
a marker to `/dev/kmsg`, do a clean `reboot`, and the marker must appear in
`/sys/fs/pstore/console-ramoops-0`. A later DTB can add `pmsg-size` if userspace markers are wanted.

## kexec, as background for 5021/5024

A load-only attempt (never executed) of the running 5019 Image, DTB, initramfs and cmdline:

```
kexec_file_load failed: Resource busy
[ 3037.217768] Can't kexec: CPUs are stuck in the kernel.
```

`/sys/devices/system/cpu/possible` = `0-13`, `online` = `0`, and `kexec_loaded` = 0 afterwards.
This confirms the 5021 diagnosis: spin-table with more than one possible CPU, so arm64 refuses.
5024 adds `nr_cpus=1`.

## Not tested

- The BT MGMT pairing-race patch (4e30208) is built in but has not been exercised. Do not pair the
  Dygma Defy as a test without a plan for recovering a wedged `hci0`.
