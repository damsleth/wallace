# Trackpad HIDF: the upload is REJECTED, it does not crash (tickets 126/197)

2026-08-02 autonomous session. CJ granted the ticket-126 exception for `a1f4131d` only
(volatile DMA, no flash). Image: `initramfs-dcuart-hidf.cpio.gz` (`e9fcd3b3`), minimal busybox +
the paired blob, nothing auto-opening inputs.

## The captured failure

```
dockchannel-hid 514600000.hid: sending firmware for multi-touch
dockchannel-hid 514600000.hid: command 0x40 to iface 0 (comm) failed with err 0xe00002c2
open-returned rc=1
```

`0xe00002c2` = **kIOReturnBadArgument** (IOKit codes: 0xe00002bc kIOReturnError, …c0 NoDevice,
…c1 NotPrivileged, **…c2 BadArgument**). The MTP coprocessor understands the command and
rejects its arguments.

## The standing belief was WRONG — correct it

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

## Prime suspect for the BadArgument: version skew

MTP reports `AppleMTPFirmwareMac-5340.61.4~438`, **SDK 25F63**. Our blob `a1f4131d` was extracted
from the **25F84** paired firmware set. A blob built against a different MTP SDK is the most
economical explanation for an argument-level rejection. Next steps (offline, good for sol):

1. Check whether a `tpmtfw-j614s.bin` exists in a 25F63-matched firmware set and compare hashes.
2. Diff our `dchid_send_firmware()` command struct against upstream's and against what the M4 MTP
   expects — note the log says **command 0x40** while `patches/t6040-dockchannel-trackpad-fw.patch`
   defines `CMD_SEND_FIRMWARE 0x95`; reconcile which field the error message prints before
   concluding the opcode is wrong.
3. Verify the DMA buffer is reachable by MTP through `mtp_dart` (a bad IOVA could also present as
   BadArgument), and that `dchid_fw_header` parsing hands the coprocessor the payload it expects
   rather than the whole file.

No crash, no flash write, nothing persistent — this experiment is cheaply repeatable.
