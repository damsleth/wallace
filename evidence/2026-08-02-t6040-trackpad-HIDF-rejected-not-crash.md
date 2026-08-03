# Trackpad HIDF: upload command accepted, post-upload reset rejected (126/197)

2026-08-02 autonomous session. CJ granted the ticket-126 exception for `a1f4131d` only
(volatile DMA, no flash). Image: `initramfs-dcuart-hidf.cpio.gz` (`e9fcd3b3`), minimal busybox +
the paired blob, nothing auto-opening inputs.

## The captured failure — and the corrected attribution

```
dockchannel-hid 514600000.hid: sending firmware for multi-touch
dockchannel-hid 514600000.hid: command 0x40 to iface 0 (comm) failed with err 0xe00002c2
open-returned rc=1
```

`0xe00002c2` = **kIOReturnBadArgument** (IOKit codes: 0xe00002bc kIOReturnError, …c0 NoDevice,
…c1 NotPrivileged, **…c2 BadArgument**). The first interpretation of this result was wrong:
the rejected command is `CMD_RESET_INTERFACE` (`0x40`), not `CMD_SEND_FIRMWARE` (`0x95`).

The applied implementation calls `dchid_send_firmware()` and checks its return before it can
call `dchid_reset_interface(iface, 0)`. `dchid_comm_cmd()` logs any nonzero coprocessor return
against that command's first byte. Therefore the preserved sequence proves that the `0x95`
command returned success at the protocol level and the following state-0 reset returned
BadArgument. It does not by itself prove that MTP consumed or applied every DMA payload byte.

The trigger excerpt is preserved at
`evidence/logs/t6040-console-20260802-ticket197-hidf-trigger-excerpt.log`; its SHA-256 is recorded in
ticket 197. At review time the rotating full console was 38,108 bytes with SHA-256
`e738ceec631dd6dc3de59f17b6e8fe8977e98e2451c677befbc76e001acffb1b`.

## The crash belief was wrong

The prior claim that "the HIDF upload crashes the boot at ~1 s" is **refuted**. The upload fails
cleanly, `open()` returns 1, and the machine continues running normally — I kept driving the
console afterwards. The earlier boot failures attributed to HIDF were something else (most likely
the same i3-image boot marginality tracked in 198).

## Mechanism, now understood end to end

`dchid_start_interface()` → `dchid_get_firmware()` reads `firmware-name` from the interface's
**named child node**, so the blob is only requested for an interface that has one, and only when
that interface starts — which happens on **first input-device open**. That is why:

- a minimal image that opens nothing never triggers it (the boot log shows no `tpmtfw` line at all);
- graphical images trigger it ~1 s in, when udev/X opens `event0`.

Our DTB does carry the node (`multi-touch { firmware-name = "apple/tpmtfw-j614s.bin"; }` via
`t6040-j614s-dcuart.dts`, confirmed present in `t6040-j614s-dcuart-wifi-cpufreq.dtb`).

## What still works without the firmware

The device enumerates and `magicmouse` binds it:

```
input: Apple DockChannel Multi-touch as …/0019:05AC:0359.0002/input/input0
magicmouse 0019:05AC:0359.0002: input: HOST HID v5.10 Mouse [Apple DockChannel Multi-touch] on 514600000.hid.1
input: Apple DockChannel Keyboard as …/0019:05AC:0359.0003/input/input1
```

So there is a registered pointer device on `event0` before any firmware upload. **Whether it
actually reports motion is untested** — that needs a human finger on the trackpad, which no agent
can supply. CJ should try the pointer in i3 and report; if basic pointing works, multitouch
gestures are the only thing the firmware buys.

## Next question: why is the post-upload reset invalid?

MTP reports `AppleMTPFirmwareMac-5340.61.4~438`, **SDK 25F63**. Our blob `a1f4131d` was extracted
from the **25F84** paired firmware set. That version skew remains a candidate for a payload that
is accepted by command `0x95` but leaves the interface unable to reset; it is no longer justified
as the prime explanation for an upload-command argument rejection. Next steps:

1. Check whether a `tpmtfw-j614s.bin` exists in a 25F63-matched firmware set and compare hashes.
2. Compare Apple's exact post-upload interface-reset sequence and state arguments with our
   `0x40, 1, iface, 0` then `0x40, 1, iface, 2` sequence. The first reset is the observed failure.
3. Verify the DMA buffer is reachable through `mtp_dart` and that HIDF parsing hands MTP the
   intended payload. Protocol success for `0x95` does not prove either property.
4. Add command-specific success/failure telemetry around `0x95` and both `0x40` calls before a
   repeat, so later evidence cannot be misattributed from a neighboring log line.

No crash, no flash write, nothing persistent — this experiment is cheaply repeatable.
