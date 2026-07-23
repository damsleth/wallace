# T6040 Alpine HID state-trace preflight

Date: 2026-07-23  
Offline ticket: 072  
Proposed rig ticket: 074  
State: **completed — FAIL; see
`done/2026-07-23-t6040-alpine-hid-state-trace-result.md`**

## Purpose

Ticket 071 disproved the DockChannel RX mask/drain/re-arm change as a
sufficient HID fix. This image instead observes the unchanged ticket-067
receive control flow at the boundaries that can still explain the failure:

- DockChannel hard-IRQ entries, flags, enabled mask, RX wakeups, drain runs,
  batches, bytes, and the final existing `DATA_RX_COUNT` read;
- DCHID mailbox callbacks, parsed command/report packets, ACK matches, comm
  events, INIT/READY interface masks, STM identity replies, deferred interfaces,
  and HID creation results.

The patch adds atomic counters, last-value snapshots, two read-only sysfs
attributes (`dc_trace` and `hid_trace`), and sparse semantic `HIDTRACE` messages.
It adds no `readl`/`writel`, polling, kick, retry, queueing, completion, IRQ-mask
operation, or new hardware address. Counter updates and messages do not select
or alter any driver branch. They are not timing-neutral, however: a changed
live outcome is evidence that instrumentation perturbed the failure, not proof
that the baseline race disappeared. `HID_STATE_TRACE=1` refuses
`HID_RX_REARM=1` and `USB_HOST=1`.

## Exact build

Build base:

```text
wallace/t6040-bringup
96ac043df12fd3b8648505c51933b1552d033c4c
```

Invocation:

```sh
cp scripts/t6040-kbuild.sh patches/*.patch \
    /Users/damsleth/Code/linux-build-out/
podman exec -e DOCKCHANNEL=1 -e HID_STATE_TRACE=1 \
    -e BUILD_DIR=/build/linux-hid-state-trace kbuild \
    bash /out/t6040-kbuild.sh image
```

Inputs added by ticket 072:

| Input | SHA-256 |
|---|---|
| `patches/t6040-dockchannel-hid-state-trace.patch` | `f966cedbc61322118d1d492726143d72364a1c3479ab2a72c9bdc08d43fbaf0b` |
| `scripts/t6040-kbuild.sh` | `7f938980410f65a4d22293d3dbd97e6227858d6b7370a790f8384564f37d94e4` |

Exported artifacts:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `Image-hid-state-trace` | 53,303,808 | `e7138c03c5dcea63048adcc5b800781a73a544699e6b575cb7343bc3f4cf4576` |
| `System.map-hid-state-trace` | 10,005,583 | `3010cc35da954f0fb26cce1fa7fc87833a9b1bc9b8337d05cf7280f212ce951f` |
| `config-hid-state-trace` | 321,996 | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |
| `t6040-j614s-dcuart-hid-state-trace.dtb` | 51,659 | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |

Boot companions remain:

| Artifact | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `initramfs-alpine-ramroot.cpio.gz` | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |

## Static verification

- Clean build completed with six jobs.
- Content/style `checkpatch.pl --strict`, excluding only the missing
  commit-message/sign-off types of this headerless integration diff: 0 errors,
  0 warnings, 0 checks. Any patch-bearing commit must use the required CJ
  Damsleth identity and `git commit -s`.
- `bash -n scripts/t6040-kbuild.sh` and build-tree `git diff --check` pass.
- The two built driver sources byte-match the reviewed post-patch sources.
- The exported config byte-matches the Image's embedded config and tickets
  067/071 (`8e11399b...`).
- The DTB byte-matches ticket 071. Decompiled inspection confirms:
  - MTP HID remains enabled on AIC input 776 with TX/RX masks 4/8;
  - DockChannel UART remains poll-mode, carrying corrected inert input 816
    and TX/RX masks 4/2;
  - all three DWC3 controllers and six USB DARTs remain disabled;
  - ANS mailbox, SART, and internal NVMe remain disabled.
- Image strings contain both sysfs attribute names and all five bounded
  `HIDTRACE` formats.
- Added patch lines contain no MMIO accessor or new scheduling, mailbox-send,
  completion, or IRQ-control call.

Independent reviewer `usb_smoke_cross_review` reproduced the hash, embedded
config, build-tree source, decompiled-DT, harness, command, and safety checks
against the final brace-clean patch and `e7138c03...` Image. Result: **PASS**;
the rig was untouched.

## Proposed one-shot run

Physical state: disconnect the bus-powered USB stick from the M4; keep the
proven DebugUSB/KIS tether on left-back; leave the other ports empty.

After independent review and explicit maintainer approval of ticket 074:

```sh
scripts/rig-lease.sh acquire codex \
    "ticket 074 Alpine HID state trace" 1394c345
RIG_AGENT=codex bash scripts/t6040-debugusb-console.sh reboot
RIG_AGENT=codex \
M1N1_BIN=/Users/damsleth/Code/linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin \
M1N1DEVICE=/tmp/m1n1 IMAGE=Image-hid-state-trace BOOT_WAIT=45 \
EXTRA_BOOTARGS= KERNEL_LOG_ARGS=ignore_loglevel \
bash scripts/t6040-boot-dcuart.sh \
    t6040-j614s-dcuart-hid-state-trace.dtb \
    initramfs-alpine-ramroot.cpio.gz
```

Exact boot arguments:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init
```

There is no `root=`.

On `/dev/ttydc0`, run only:

```sh
cat /etc/alpine-release
apk --print-arch
dmesg | grep HIDTRACE
for f in /sys/bus/platform/devices/*/dc_trace \
         /sys/bus/platform/devices/*/hid_trace; do
    [ -r "$f" ] || continue
    echo "=== $f ==="
    cat "$f"
done
cat /proc/bus/input/devices
ls -l /dev/input
cat /proc/partitions
```

The experiment succeeds if Alpine/ttydc0 remains responsive, the bounded trace
files are captured, `/proc/partitions` remains empty, and no safety stop occurs.
Whether HID registers is an observed branch, not permission for follow-up
commands. Stop after the listed capture. Do not load modules, mount anything,
configure networking, invoke `apk add`, or probe devices.

Stop immediately on async SError, reset/watchdog loop, DART fault, any
USB/ANS/NVMe probe, unexpected block device, lost DockChannel, missing trace
attributes, or a non-responsive shell. Recover a stable `Running proxy...`
before releasing the lease.

## Interpretation

- MTP `irq_calls/irq_wakes/rx_batches = 0`: stop is at or before local
  DockChannel IRQ delivery.
- DockChannel RX bytes but no DCHID callback/packet count: stop is at the
  mailbox-client boundary.
- Parsed reports but no comm events: stop is in report classification/work
  dispatch.
- INIT without STM READY, or READY without matched identity ACKs: stop is in
  the indicated DCHID lifecycle stage.
- Successful STM identity with missing `create_ok` bits: stop is interface
  deferral/creation.

No outcome justifies an unreviewed receive kick, retry, or new MMIO access.
