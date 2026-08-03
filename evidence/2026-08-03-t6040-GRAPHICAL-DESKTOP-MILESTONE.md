# 🎉 MILESTONE: self-starting i3 desktop on a persistent root (ticket 213)

2026-08-03. The M4 Pro now boots, unattended, from its own persistent filesystem straight into a
graphical desktop on the internal panel.

## Verified after a cold reboot, with no console interaction

```
ps            -> Xorg, i3bar, i3status all running
i3-msg -t get_version    {"major":4,"minor":24,"patch":0,"human_readable":"4.24 (2024-11-06)",
                          "loaded_config_file_name":"/etc/i3/config"}
i3-msg -t get_workspaces [{"num":1,"name":"1","visible":true,"focused":true,
                           "rect":{"x":0,"y":23,"width":3024,"height":1867}}]
df /          /dev/loop0   5.8G   371M   7%   /
```

**3024×1867** is the native panel resolution minus the 23 px i3bar — this is the real internal
display via simpledrm + Xorg `modesetting`, not a virtual screen. Root is the ext4 image on the SD
card, so the whole system (including everything below) survives power cycles.

## What the machine does now, from cold, by itself

| | |
|---|---|
| Boot chain | enrolled m1n1 (no proxy wait) → 1.8 MB initramfs → loop-mount ext4 on SD → `switch_root` |
| Root filesystem | persistent, 197 Alpine packages, 5.8 GiB image on a 58.2 GiB SDXC card |
| Desktop | Xorg + i3 4.24 + i3bar/i3status on the native panel, Norwegian keymap |
| Console | shell on ttydc0 for host-side driving |
| Also live | OpenRC, D-Bus, Bluetooth, cpufreq, SPMI RTC (real dates), keyboard backlight |

## Two bugs found and fixed getting here

1. **`xinit`/`startx` is unusable in this configuration.** It exits immediately and takes X with it,
   even with a valid hostname. The working path is to launch `/usr/libexec/Xorg` and `i3` directly.
   `scripts/t6040-sdroot-startx` does that.
2. **A hostname race killed the first autostart attempt.** As an inittab `::once:` entry the script
   runs ahead of OpenRC's hostname service, so `xauth` built the display name `"(none):0"`, failed,
   and i3 could not authenticate — X then exited. The script now runs `hostname -F /etc/hostname`
   itself before touching X. The symptom (`xauth: bad display name "(none):0"`) is worth remembering:
   it looks like an X problem and is actually a boot-ordering problem.

## Boot it

```
BOOT_MAXCPUS=1  EXTRA_BOOTARGS='console=ttydc0'   initramfs-sdroot.cpio.gz
```

`maxcpus=1` is deliberate and currently required: ticket 205's CoW corruption makes >=2 cores unsafe
(processes die at 2, PID 1 dies at 3+). Everything above is unaffected by that bug — it is purely a
core-count limit, so lifting 205 turns this same system into a multi-core daily driver with no other
work.

## Not yet working on this root

- **WiFi**: `wlan0` does not appear — the brcmfmac firmware set on the card is incomplete (only the
  `-a`/BT variants are present, not the `-u` WLAN blobs the driver requests). Ticket 214.
- **NVMe file I/O**: ticket 206/210, unrelated to this root.
- **Trackpad multitouch**: ticket 212; the pointer may already work via `magicmouse`.
