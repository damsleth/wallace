# T6040 internal keyboard restored — hid->type fix (tickets 077 + 078, 2026-07-24)

The HID regression that blocked the internal keyboard on every current-kernel
untethered boot is **fixed and live-verified**.

## Root cause (077 decode — driver diff + the 076 live trace)

Active driver is `drivers/hid/apple-dockchannel-hid/apple_dockchannel_hid.c`
(not the sibling `dockchannel-hid.c`). It registers each interface as its own
`hid_device` via `hid_add_device()` (`:576`) but **never sets `hid->type`**, so
every iface (keyboard included) stays `HID_TYPE_OTHER`.

The rebased hid-apple (Asahi "HID: apple: Bind to HOST devices for MTP",
`4cdbfc2864a2`, pulled via the 7.1 core-v2 merge) now:
1. id-table matches **any** `BUS_HOST` Apple device (`HOST_VENDOR_ID_APPLE=0x05ac`);
2. `apple_probe` (`hid-apple.c:984`) returns `-ENODEV` unless
   `hdev->type == HID_TYPE_SPI_KEYBOARD`.

Chain for the keyboard iface: `hid_add_device` → `device_add` succeeds
(`create ret=0`, the 076 trace) → hid-apple matches → `apple_probe` bails
`-ENODEV` (type is OTHER) → hid-generic then declines (`__check_hid_generic`
sees hid-apple "matched") → **nothing binds → no `hidinput` → no `/dev/input`**.
`hid_add_device`'s 0 return says nothing about the later async bind, so the
driver reported success while the bind silently failed. This refutes the earlier
DockChannel-RX-race and composite-multitouch hypotheses (each iface is separate;
076 proved HID RX delivers 1396 B). The sibling `dockchannel-hid.c` sets
`hid->type`; the active driver omitted it — the regression rode in with the
hid-apple rebase.

## Fix (078) — `patches/t6040-dockchannel-hid-type.patch`

Six lines in `dchid_create_interface_work`, before `hid_add_device`, mirroring
the sibling: `hid->type = HID_TYPE_OTHER;` then `"multi-touch" → HID_TYPE_SPI_MOUSE`,
`"keyboard" → HID_TYPE_SPI_KEYBOARD`. Driver-only — no MMIO/PMU/SPMI, safest
class. Built onto the state-trace kernel: live-proven `Image-hid-type-fix`
`df7657c15ad73a486f5046bcc802f070d6b7ec071fb6bb70954fb8f222d4815a`.
`scripts/t6040-kbuild.sh` carries it behind explicit `HID_TYPE_FIX=1`; unrelated
historical candidates therefore retain their exact source.

The live artifact was an incremental build. Two forced relinks with fixed build
metadata instead match each other at
`ac330436590436344622823d1c7d4e1caac2f06b4a75f9ca9dea94972da9b0cc`
(same source/config, not yet live-tested). Keep `df7657c1...` as the exact
hardware-proven input and use the reproducible successor only after its own
exact-hash gate.

## Live result — keyboard registers

Rig retest (m1n1 upper-guard `1394c345`, DTB `2782b922`,
`initramfs-alpine-hid-trace-auto` `d5b790c6`, `t6040.hid_trace_auto=1`, Alpine
RAM-root, maxcpus=1; lease held+released healthy;
`evidence/logs/t6040-console-20260724-078-hid-fix.log`):

```
[/proc/bus/input/devices]
I: Bus=0019 Vendor=05ac Product=0359 Version=0510
N: Name="Apple DockChannel Keyboard"
S: Sysfs=/devices/platform/soc/514600000.hid/0019:05AC:0359.0003/input/input0
H: Handlers=sysrq kbd leds event0
B: EV=120013  B: KEY=...  B: LED=1f
[/dev/input]
crw-------  1 root root  13, 64  event0
```

`event0` with the full `kbd` handler + LEDs, on Alpine RAM-root over ttydc0. The
074/076 empty-`/dev/input` state is resolved. This run proves registration, not
yet local typed-key echo; ticket 083 owns that on-device check. (Trackpad
multi-touch still needs
`HID_MULTITOUCH` present — a module absent from this RAM initramfs — a separate,
non-blocking follow-up.)

## Impact

The internal keyboard registration blocker for a *usable* untethered distro is
now fixed on the current kernel. Remaining untethered pieces: on-device fbcon
login (083, needs this fixed HID — now unblocked), enrollment/cold-boot
(081/082, Sol), and the distro progression (Alpine RAM-root boots; Ubuntu-in-RAM
next). Tickets 077 + 078 done.
