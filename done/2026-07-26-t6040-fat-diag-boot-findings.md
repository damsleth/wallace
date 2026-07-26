# Fat kernel diag boot: simpledrm probes, and what the panel artefacts really were

The 17:31 run of `m1n1-b0-dwm-fat-diag.bin` (`d14df9f3`) booted to Linux userspace. Object identity
confirmed by `Loading kernel image (0x4f58004)` = 83,197,952 + the 4 bytes `chainload.py` appends.

## Both known graphical blockers are cleared

From the panel dmesg:

```
[drm] Initialized simpledrm 1.0.0 for 105d306a880.framebuffer on minor 0
Console: switching to colour frame buffer device 189x59
simple-framebuffer 105d306a880.framebuffer: [drm] fb0: simpledrmdrmfb frame buffer device
```

**simpledrm probed cleanly.** That was ticket 148's stated risk — DIET drops `DRM_TTM`, `DRM_SCHED`
and `DRM_DISPLAY_HELPER`, and 148 warned `modesetting` might therefore fail to probe simpledrm. The
full kernel has those helpers and DRM came up. Combined with `CONFIG_UNIX` being present (the AF_UNIX
absence that actually killed 148's Xorg), **both known blockers to the graphical target are gone.**
Whether `modesetting` then drives it is still untested — that is what the plain object answers.

Also visible, and relevant well beyond dwm:

- `usbcore: registered new interface driver usb-storage` and `uas` — the fat kernel has USB mass
  storage, which the diet kernel lacked. Directly useful to ticket 138 once the HPM/ATC link lands.
- `apple-dart 514800000.iommu: DART [pagesize 4000, 16 streams, bypass support: 1, bypass forced: 1,
  locked: 0, AS 42 -> 42] initialized`
- `apple-dockchannel 50880c000.mailbox: using polled mode (5 ms)` — the UART dockchannel is polled,
  the conservative proven path.
- MTP firmware `AppleMTPFirmwareMac-5340.61.4~438`, personality `MTP_SYS`, SDK `25F63`, built
  2026-04-18.
- Plenty of generic drivers (`e1000`, `igb`, `megasas`, `thunder_xcv`, `VFIO`, `tun`, `loop`) — the
  expected, harmless cost of a capability-first kernel.

## The panel artefacts: corrected explanation

The screenshot showed a duplicated block of dmesg and overlapping/ghosted glyphs. Timestamps run
`0.090689` → **backwards** to `0.039262` → … → `0.090689` again, which is a **ring-buffer replay**,
not corruption.

**An earlier explanation of mine was wrong.** I attributed it to *two* `CON_PRINTBUFFER`
registrations (`tty0` plus `ttydc0`). That is impossible: the shipping DockChannel driver registers no
console at all (ticket 159 / 153), so `ttydc0` never registered and `console=ttydc0` was inert. The
duplication is the **single** normal replay when fbcon takes over from the boot console
(`Console: switching to colour frame buffer device`), and the glyph corruption is fbcon being written
from both the replay and live-printk contexts.

Consequence: **this is not caused by the diagnostic bootargs and will appear on the plain object too.**
It is cosmetic, and expected on any image with `ignore_loglevel` on this fbcon.

## Why the host log stayed empty

`console=ttydc0` matched no registered console, so no kernel dmesg ever left the machine — the
post-handoff console log was 0 bytes. `/dev/ttydc0` does exist, which is why a **userspace** getty
works and how the ticket-147 B0 health report reached the host. Full root cause in
`done/2026-07-26-t6040-dockchannel-tty-provenance.md`.

The fix is now one rebuild away: `patches/t6040-dockchannel-nbcon.patch` adds a real
`register_console` and, **verified today, applies cleanly** on top of the recovered driver patch. It
was deliberately not built yet, so that the maintainer's pending test of `c5438779` changes only one
variable. (`t6040-dockchannel-atomic-tx.patch`, the other orphan, remains **untested** — the scratch
tree used for the check lacked `drivers/mailbox/`.)
