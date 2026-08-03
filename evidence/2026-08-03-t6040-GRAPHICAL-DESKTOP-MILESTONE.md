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

---

# 🏁 COMPLETE: WiFi on the persistent root — the machine is now self-sufficient (ticket 214)

Everything below was read **over SSH from the host**, on a machine that cold-booted with no console
interaction:

```
=== SSH INTO THE M4 ===
t6040
7.1.3-g1c1acd21b13a-dirty
1
/dev/loop0                5.8G    375.6M      5.1G   7% /
--- desktop ---
Xorg / i3bar / i3status
[{"num":1,"name":"1","visible":true,"focused":true,"rect":{"x":0,"y":23,"width":3024,"height":1867}}]
--- radios ---
Connected to fc:22:f4:16:72:1c (on wlan0)   SSID: Bilbo Laggins   freq: 2412.0
hci0:  Type: Primary  Bus: PCI   BD Address: 84:2F:57:2E:B1:88
```

WLAN firmware: `BCM4388/6 wl0 … version 23.50.20.0.41.51.208 FWID 01-ef259bc2`, with the TxCap and
calibration blobs both accepted.

## Root cause of the missing wlan0 — a timing bug, not missing files

My first read of this was **wrong** and worth recording: I concluded the card's brcmfmac firmware set
was incomplete because a truncated `ls | head -4` showed only BT blobs. A full listing proved every
WLAN blob was present, including `brcmfmac4388c0-pcie.apple,mriya-WLMT-u.bin`.

The actual cause is **ordering**: brcmfmac probes at **0.65 s**, while `switch_root` into the SD root
happens at **~3.5 s**. When the driver asks for firmware, the only root is the 1.8 MB initramfs, which
had none — so the request fell through to the generic `brcmfmac4388c0-pcie.bin` and failed with -2.

**Rule: any driver that requests firmware during probe needs that firmware in the INITRAMFS, not on
the real root.** Putting files on a root that is mounted later cannot help a driver that probes
earlier. This applies to brcmfmac, hci_bcm4377, and the trackpad HIDF blob.

Fix: stage the WLAN+BT firmware into `initramfs-sdroot.cpio.gz`, preserving the **c2-content-under-c0-names**
mapping (verified by hash: `brcmfmac4388c0-pcie.apple,mriya-WLMT-u.bin` → `7cfae862…`, the c2 blob).
The initramfs grew 1.8 → **8.8 MB expanded**, still 11x smaller than the 99 MB image that loses the
`unpack_to_rootfs` race, so the SMP margin is preserved.

## The machine, as it now stands

| capability | status |
|---|---|
| Cold boot to graphical desktop, unattended | ✅ i3 4.24 on the native 3024×1867 panel |
| Persistent root | ✅ ext4 on SD, survives power cycles |
| WiFi | ✅ associated, DHCP lease, **reachable over SSH from cold boot** |
| Bluetooth | ✅ `hci0` up, BD `84:2F:57:2E:B1:88` |
| Keyboard backlight | ✅ CJ-verified, keys light |
| RTC / cpufreq / SMC / SD | ✅ |
| Cores | ⚠️ **1** — ticket 205 (CoW corruption) caps this, nothing else does |
| NVMe file I/O | ❌ ticket 206/210 |
| Trackpad multitouch | ❌ ticket 212 (pointer via magicmouse may already work) |
| USB | ❌ knowledge-blocked (no VBUS command exists in Apple's stack) |

**The serial tether is no longer required for userspace work.** Future iteration is `ssh root@<ip>`
plus editing files on a persistent filesystem — no rebuilds, no re-enrolment, no proxy window.
