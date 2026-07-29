# 🚀 Daily-driver object c1529d4c — i3 + cpufreq@4.5GHz + WiFi + BT + /data (2026-07-30)

Autonomous overnight session. **Ready to enroll:**

```bash
kmutil configure-boot -c /Volumes/S128/m1n1-dwm-i3-everything-cpufreq-5core.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/m1n1
```

`m1n1-dwm-i3-everything-cpufreq-5core.bin`
SHA-256 `c1529d4c8007e251606f14a86e6d307aad04b3472f2527c41f01b85c58072773`,
42,745,856 B = **2609 × 16 KiB exactly**. Allowlisted in `scripts/t6040-enroll-guard.sh`.
Rollback remains `rollback-m1n1-1394c345.bin`. The M4 is parked at the rollback proxy.

## What you get on the panel

i3 (Super/cmd = mod; Enter=terminal, d=dmenu, Shift+e=exit to dwm-less X) with dwm still in the
image, Norwegian layout, HiDPI. Keyboard works. **Trackpad does not** (see below — deliberate).
ttydc0 getty (drive it from the host: `printf 'cmd\n' > /tmp/m1n1`). 7 GiB tmpfs at `/data`;
insert an SD card (or a USB stick, the day VBUS exists) and it automounts to `/mnt/sd` with
`t6040-data-sync` persisting /data onto it.

## Members (strict verify PASS, `--expect-bootargs` pinned)

| member | sha256 | notes |
|---|---|---|
| m1n1 | `ee58fa40…` | same PCIe-V1 dual-mode prefix as 187, 10 s DTR window |
| kernel (gzip) | `860dc03e…` | `Image-…-cpufreq`: + apple-cpufreq (overflow patch), HID_MAGICMOUSE, vfat/exfat/ext4/USB-storage |
| dtb | `3b9235cd…` | **new combined** `t6040-j614s-dcuart-wifi-cpufreq.dtb` (pwren + antenna + cpufreq) |
| initramfs (xz) | `ce55556e…` | i3+dwm, wifi/bt userspace, brcm fw (c2-under-c0), data-mount/sync, getty, **no HIDF** |
| bootargs | `maxcpus=5 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 console=ttydc0 ignore_loglevel rdinit=/sbin/init` | |

Initramfs decodes to 99.5 MiB in the minilzlib harness (limit ~128 MiB).

## Live verification (chainloaded, exact member combination, tonight)

```
policy0 cpu0     1260000-4512000   performance -> 4512000  (P cluster at full M4 Pro boost)
policy1 cpu1-4   1020000-2592000
wlan0: iw scan -> 19 BSS           hci0: present
/data: 7.0G tmpfs                  Xorg + i3 + i3bar + i3status running
```

## Two more root causes found tonight (both fixed in this object)

1. **Every dwm-image boot since ~07-28 hung at the Asahi logo** (your repeated "asahi logo, no
   text"): `t6040-usb-acm-console` ran as a *sequential* `::sysinit:` inittab entry, and its
   configfs UDC bind blocks in-kernel forever when dwc3 is wedged after chainload handoff. Getty
   and X never started. Moved to `::once:` + `timeout 10` on the bind. A/B verified.
2. **The trackpad's real driver is hid-magicmouse, not hid-multitouch** (BUS_HOST entry + J314
   tables). With only MULTITOUCH the Multi-touch HID device sat unbound and the tpmtfw request
   never fired. TRACKPAD_FW now enables+asserts MAGICMOUSE.

## Why NO trackpad firmware in this object (126 exception used, then withdrawn from the object)

With the a1f4131d blob in the image and magicmouse bound, the machine **dies silently** the moment
the interface opens and dchid uploads the firmware + resets the trackpad. A/B/A bisected tonight:
everything-image+old-kernel = alive; everything+magicmouse+blob = dead (~1 s, before ttydc0);
minimal+magicmouse+no-blob = alive; everything+magicmouse+no-blob = alive (this object). Post-
mortem ramdump is impossible — warm reboot scrubs/re-keys DRAM (read back all-zeros at the
verified `__log_buf` phys addr). **Next step needs you at the panel**: boot the HIDF variant
tethered and photograph the panic (`console=tty0` will show it). Ticket 126 updated.

## Also done tonight (separate docs)

- **NVMe READ WORKS** — `done/2026-07-30-t6040-NVME-READ-WORKS.md` (GPT `EFI PART` read from the
  internal SSD via reg[9]; V_UNKNOWN FW-gate fix was load-bearing).
- **cpufreq root cause** — `done/2026-07-30-t6040-006-SOLVED-cpufreq-32bit-overflow.md` (upstream
  32-bit overflow; M4 is the first Apple silicon to trip it). **Draft for upstream** with the NVMe
  reg_len + V_UNKNOWN items.
- IRC 07-29: yuka's t8122 SD-reader ltssm notes (we're unaffected); sven actively on M4 SPTM
  (EL2/GL2 emulation) — good moment for your J614s-access offer.
- kbd-backlight: HID route ruled out (no 0xff00/0x0f usage in the keyboard rdesc); next candidate
  is the ADT `kbd-backlight` node decode. Panel backlight is DCP-gated (big ticket).
