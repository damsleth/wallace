# 🐧 Graphical target COMPLETE: dwm with a working keyboard on the M4 Pro panel

Object `m1n1-b0-dwm-udev.bin` (`3ec81ef3`) is a **pass**. Maintainer-confirmed on the internal panel:

- **dwm running** — tags 1–9, `[]=` tiled layout, `st`, `dwm-6.8`, blue selected-window border
- **keyboard works** — `Alt+Shift+Return` spawns a new terminal, `Alt+p` opens dmenu
- **Norwegian layout correct** — æ ø å, via `setxkbmap no`
- trackpad still dead, as designed and expected (tickets 004/126)

So the whole chain works: enrolled-format raw object → m1n1 → full kernel → Alpine RAM root → Xorg on
`modesetting`/simpledrm → dwm → `st` → keyboard input.

## What the two fixes were

| | Symptom | Cause | Fix |
|---|---|---|---|
| 148 | Xorg fatal, `Cannot establish any listening sockets` | diet kernel had `# CONFIG_NET is not set`, so no `CONFIG_UNIX` and no AF_UNIX socket | full kernel |
| 161 | dwm loaded, no input at all | image had `libudev.so.1` as a dependency but **no `udevd`/`udevadm`**, so the udev database was empty and `xf86-input-libinput` enumerated zero devices | install and start `eudev` before X |

Neither was the failure ticket 148 predicted (it expected the simpledrm probe or a missing pointer to
be the problem). `simpledrm` in fact probed cleanly the first time the full kernel ran.

## Remaining cosmetic issue: text was extremely small — fixed

The panel is 3024×1964 on a 14.2″ display ≈ **254 DPI**, while X assumes 96, so everything rendered at
roughly a quarter of its intended physical size.

The existing `xrandr --dpi 192` line **could never have fixed `st`**, and that is the interesting part:
Alpine builds `st` with a **`pixelsize=`** font, and a pixel size is immune to every DPI setting. Three
mechanisms are needed because they do not share a source of truth:

1. **the X server's own DPI** (`startx -- -dpi 192`) — what the display reports;
2. **`Xft.dpi`** via `~/.Xresources` + `xrdb -merge` — what Xft actually consults for **point** sizes.
   This is what scales **dwm's bar and dmenu**, whose fonts are compile-time `monospace:size=10`
   (suckless configs are baked into the binary, so they cannot be changed without rebuilding dwm and
   dmenu — Xft.dpi is the only lever available on a packaged build);
3. **an explicit font for `st`** — `st -f 'monospace:pixelsize=28'`, since its pixelsize ignores DPI.

`xrdb` was added to the image (it was not previously installed, so `Xft.dpi` could not have been loaded
at all). Both values are overridable at boot: `T6040_DPI` (default 192 = 2× the 96 baseline, the usual
HiDPI convention) and `T6040_ST_PIXELSIZE` (default 28). Verified by simulating the generated script:
defaults produce `Xft.dpi: 192` and `pixelsize=28`, and `T6040_DPI=254 T6040_ST_PIXELSIZE=36` correctly
produces those instead — worth knowing since 254 is the panel's true DPI if physically accurate sizing
is wanted over the 2× convention.

## The object

`m1n1-b0-dwm-hidpi.bin`
`59622e78685961a322308643b03eae6db0dd3ee985b5674e0b3e6831d605a270`
**28,459,008 B = 1737 × 16 KiB**, strict verify **PASS**, kernel `pages=4K`.

Members are identical to the working `3ec81ef3` except the initramfs (`47d1e8ce`, 15.17 MiB xz →
~62 MiB expanded), which adds `xrdb` and the HiDPI startup. Bootargs remain the proven `3659a0da` set.

**Versus the object that works, exactly one thing changed: font/DPI handling.** Nothing in the kernel,
loader, DTB or bootargs moved, so this cannot regress the input or graphics result.

## Run it

```sh
bash scripts/t6040-debugusb-console.sh reboot
bash scripts/t6040-boot-raw-object.sh \
    ~/Code/linux-build-out/m1n1-b0-dwm-hidpi.bin \
    59622e78685961a322308643b03eae6db0dd3ee985b5674e0b3e6831d605a270
```

If 28 px still reads small or now too large, the dial is `T6040_ST_PIXELSIZE`; the dwm bar and dmenu
follow `T6040_DPI`. Both can be tuned without a rebuild by editing `/usr/local/sbin/t6040-startx` on a
running system, but a new object is needed to persist it.
