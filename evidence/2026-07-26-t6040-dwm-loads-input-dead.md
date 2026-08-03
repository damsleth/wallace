# dwm loads on the panel — the graphical target is reached; input is the remaining gap

## Result: dwm is running

`m1n1-b0-dwm-fullkernel.bin` (`6738aad9`) booted and the maintainer reports, on the internal panel:

- tags **1–9** in the top left
- **`[]=`** — dwm's tiled layout indicator
- **`st`** as the window title
- **`dwm-6.8`** top right (dwm's default status text)
- a **blue border** around the selected window, and a shell prompt `/#` inside `st`
- a mouse cursor parked in the centre of the screen

That is unmistakably dwm with `st` running. **Xorg started, `modesetting` drove simpledrm, and dwm
loaded** — so every blocker identified across tickets 148/155 is cleared:

| Blocker | Status |
|---|---|
| `CONFIG_UNIX` / AF_UNIX socket (killed 148's Xorg) | fixed by the full kernel |
| `DRM_TTM`/`DRM_SCHED`/`DRM_DISPLAY_HELPER` (148's predicted risk) | present; `simpledrm` probed |
| `modesetting` actually driving simpledrm (untested until now) | **works** |
| initramfs decode (the fat object's failure, ticket 160) | avoided: 62.3 MiB expanded |

**Neither keyboard nor mouse responds.**

## Cause: there was no udev at all

`xf86-input-libinput` discovers and classifies input devices through **libudev**. The image contained
`libudev.so.1` — pulled in as a dependency of Xorg/libinput — but **no `udevd` and no `udevadm`
binary**, so the udev database was never populated and Xorg's auto-add enumerated **zero** devices.
It is not that the keyboard was missing: `event0` is present and works at the console (the B0 health
report has consistently shown `Handlers=sysrq kbd leds event0` for the `Apple DockChannel Keyboard`).

The dead **mouse** is separate and expected — the trackpad is unsupported (tickets 004/126), which is
also why the design deliberately sets `AllowMouseOpenFail true` and picks a keyboard-driven WM.

## Fix

`eudev` is now installed, and `t6040-startx` starts it **before** X, which is the standard Alpine
arrangement:

```sh
/sbin/udevd --daemon
/bin/udevadm trigger --type=subsystems --action=add
/bin/udevadm trigger --type=devices --action=add
/bin/udevadm settle --timeout=10
```

Verified present in the built image: `/sbin/udevd`, `/bin/udevadm`, `/sbin/udevadm`, and **28 udev rule
files** including `60-input-id.rules` — which is exactly what sets `ID_INPUT_KEYBOARD`, the property
libinput classifies on — plus `80-libinput-device-groups.rules` and `90-libinput-fuzz-override.rules`.

The script now also writes diagnostics to `/var/log/xorg-startx.log` **before** starting X:
`/proc/bus/input/devices`, `ls -l /dev/input`, and `udevadm info --query=property
--name=/dev/input/event0`. Each rig cycle costs a reboot, so a failure should be readable in one pass
instead of needing another boot to establish whether the device was even there.

## The object

`m1n1-b0-dwm-udev.bin`
`3ec81ef3f81d09a8cea0d77017067a07f93d2c6ea1c360464d6c183593ffe875`
**28,475,392 B = 1738 × 16 KiB**, strict verify **PASS**.

| Member | Hash | Note |
|---|---|---|
| m1n1 v7 window-free | `ecd264a5…` | unchanged |
| kernel `Image-hid-type-fix.xz` | `cbb3e743…` | full kernel, `pages=4K` |
| DTB | `2782b922…` | storage-disabled |
| initramfs `initramfs-alpine-dwm-udev.cpio.xz` | `514302be…` | 15.17 MiB xz → **62.3 MiB** expanded |
| bootargs | `3659a0da…` | proven B0 set |

Versus `6738aad9`, which loaded dwm, **exactly one thing changed: eudev is installed and started.**

## Run it

```sh
bash scripts/t6040-debugusb-console.sh reboot
bash scripts/t6040-boot-raw-object.sh \
    ~/Code/linux-build-out/m1n1-b0-dwm-udev.bin \
    3ec81ef3f81d09a8cea0d77017067a07f93d2c6ea1c360464d6c183593ffe875
```

Pass = a keystroke reaches `st`. dwm's default binds are `Alt+Shift+Return` for a new terminal and
`Alt+p` for dmenu, so either is a quick check. The Norwegian layout is applied by `setxkbmap no` in
`.xinitrc`; æ ø å are the test. The trackpad is still expected to be dead.

If input is still absent, read `/var/log/xorg-startx.log`: the pre-X diagnostics will show whether
udevd started, whether `event0` exists, and whether `udevadm info` reports `ID_INPUT_KEYBOARD` — which
distinguishes "udev not running" from "libinput did not claim the device" from "X never saw it".
