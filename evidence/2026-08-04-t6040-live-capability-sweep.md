# Live capability sweep on the SD root, 2026-08-04

Run over a serial shell on `ttydc0` with the always-proxy rollback object enrolled,
booting `t6040-j614s-dcuart-wifi-nonvme.dtb` + the hardened initramfs at `maxcpus=1`.

## SD — WORKING, signed off

| step | result |
|---|---|
| reader enumerates | `GL9755 present after 0s`, `sdhci-pci bound after 0s` |
| dirty exFAT repaired | `fsck.exfat` ran, volume mounted |
| ext4 loop root | `/dev/loop0 / ext4 rw,relatime` |
| capacity | 5.8 G total, 375.8 M used, 5.1 G free |
| **persistence across reboot** | `2f8ac261b902efba4bbd4223bee7d693` **identical** before and after |
| kernel faults | **0** |

Writing a 64 KiB random file, syncing, rebooting, and re-hashing gives a byte-identical
result. SD read/write persistence is proven on this exact stack.

## GUI — WORKING

`Xorg` (pid 479), `i3` (463), `i3bar` (622) and `i3status` (624) all running on the
SD root. The desktop comes up unattended.

## Keyboard layout — FIXED, and it was wrong at the X layer

The console keymap loads from the initramfs (`Norwegian console keymap loaded`), but
X reported `layout: us`. The card's `t6040-startx` predated the fix and its
`setxkbmap no` was silenced with `2>/dev/null`. `setxkbmap` exists and exits 0, so
the failure was environmental (auth/timing) and invisible. Fixed live —
`layout: no` — and made persistent via `/etc/X11/xorg.conf.d/00-keyboard.conf`.

## Bluetooth — WORKING

`hci0: Type: Primary  Bus: PCI`.

## WiFi — RADIO WORKS, 2.4 GHz BAND IS BLIND (ticket 229)

Firmware loads cleanly: `BCM4388/6 … version 23.50.20.0.41.51.208`, with the TxCap
blob and the platform calibration blob both accepted.

Two findings, and the first is a trap worth remembering:

1. **A scan returning zero networks did not mean broken WiFi.** A `wpa_supplicant`
   instance (in fact two, colliding — `nl80211: kernel reports: Match already
   configured`) was holding the radio and starving `iw scan`. After
   `killall wpa_supplicant`, the same scan returned **75 SSIDs** immediately.
2. **2.4 GHz sees nothing while 5 GHz works.** `grep -c "freq: 5"` → **47**;
   `grep -c "freq: 2"` → **0**. The configured SSID `Bilbo Laggins` never appears,
   and `wpa_state` stays `SCANNING`. If that AP is 2.4 GHz, this is exactly why it
   cannot associate.
3. `/lib/firmware/regulatory.db` is **missing**, so `iw reg set NO` silently does
   nothing and the domain stays `country 00`. Under country 00, 2402–2472 is still
   permitted, so this does *not* by itself explain the blind 2.4 GHz band — but it
   should be fixed regardless, and it does restrict 5 GHz to passive scan.

Non-fatal firmware complaints seen at boot: `brcmf_c_set_joinpref_default: Set
join_pref error (-52)` and `brcmf_dongle_roam: WLC_SET_ROAM_DELTA error (-52)`.

## Trackpad — ENUMERATION IS COMPLETE AND CORRECT (ticket 212)

`input0: Apple DockChannel Multi-touch`, `capabilities/abs = 67f800001000003`, which
decodes to:

```
ABS_X, ABS_Y, ABS_PRESSURE,
ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR, ABS_MT_TOUCH_MINOR,
ABS_MT_WIDTH_MAJOR, ABS_MT_WIDTH_MINOR, ABS_MT_ORIENTATION,
ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID, ABS_MT_PRESSURE
```

That is a full, correct multitouch contract — slots, per-contact position, tracking
IDs and pressure. So the device is not mis-enumerated and the evdev side is sound;
the only remaining question is whether HID reports actually arrive when the surface
is touched. **That needs a finger on the trackpad and cannot be tested unattended.**
One second of CJ's time settles it: touch the pad and see whether the pointer moves,
or run `cat /dev/input/event0 | wc -c` while touching.

## USB — nothing bound

`/sys/bus/usb/devices` and `/sys/class/udc` list nothing; only `usbcore`/`usbhid`
registration appears at boot. Host mode remains unproven, as expected.
