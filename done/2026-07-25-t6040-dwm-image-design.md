# T6040 graphical target (Alpine + Xorg + dwm) — sizing and design (2026-07-25)

Ticket 142 design pass, done before building so the approach is grounded.

## Package closure, measured from the real Alpine 3.24 aarch64 indexes

Seeds `xorg-server xf86-input-libinput dwm st dmenu font-terminus xinit setxkbmap`
resolve to **27 named packages**:

```text
download   21.5 MiB
installed  55.8 MiB
```

Largest contributors: **mesa 35.6 MiB**, font-liberation 4.2, font-misc-misc 4.0,
xorg-server 3.3, xkeyboard-config 3.2, font-terminus 2.2.

All of `xorg-server`, `xf86-input-libinput`, `libinput`, `dwm`, `st`, `dmenu`, `xinit`,
`setxkbmap` are in Alpine **community**, not main — the B0 build script only pins `main`
packages, so the repo list needs extending.

## The design decision this changes

I had planned to avoid Mesa (Xorg `modesetting` with `AccelMethod "none"`/shadowfb needs no
GL for 2D). Two facts kill that contortion:

1. **Alpine's `xorg-server` hard-depends on mesa** — it is not optional at the package level.
2. **Object size is not a constraint**: ticket 137 proved enrolled objects load in full at
   least to 256 MiB, and the current graphical projection is far below that.

Projected image: root ~13 MB (current B0) + ~56 MB → ~70 MB raw → roughly **25 MiB xz**, so
an object near **31 MiB** — comparable to the already-booting 22.6 MiB Ubuntu object.

So: **take the whole stack, including software Mesa.** Two bonuses follow.

- **llvmpipe software GL** comes along, so GL applications work (slowly) instead of not at
  all.
- It moots my earlier objection to Wayland/`dwl` (ticket 144), which I had argued was
  impractical because wlroots wants GLES2 → Mesa. With Mesa present anyway, `dwl` becomes a
  realistic sibling experiment; the remaining unknown there is still wlroots' DRM backend on
  `simpledrm`, not the renderer.

## Kernel

The B0 `DIET=1` kernel already has `DRM`, `DRM_SIMPLEDRM`, `DRM_FBDEV_EMULATION`, `INPUT`,
`INPUT_EVDEV`, `UNIX98_PTYS` and `TMPFS`, which is what Xorg's `modesetting` driver plus
libinput need. Risks to verify at first boot rather than assume:

- I disabled `DRM_TTM`, `DRM_SCHED`, `DRM_DISPLAY_HELPER`, `DRM_PANEL`, `DRM_BRIDGE` in the
  diet. `simpledrm` should need none of them, but if Xorg's modesetting probe fails, a
  graphical-capable diet variant is the fix.
- Xorg with **no pointer device** (the trackpad is still unsupported, tickets 004/126).
  `xf86-input-libinput` plus the `event0` keyboard should satisfy it; dwm is keyboard-driven
  so a missing pointer is not a functional loss.

## suckless configuration is compile-time

`dwm`, `st` and `dmenu` bake keybindings in at build time, so the Alpine binary packages ship
upstream defaults. For a Norwegian keyboard the sane first cut is: keep the default `MODKEY`
(Alt), rely on `setxkbmap no` for the layout, and accept defaults elsewhere; only rebuild
from source if the defaults prove unusable. Changing them later means rebuilding the object,
so it is worth checking the defaults on the panel before investing in a custom config.

## Build approach

The B0 script installs only network-free, hash-pinned `main` `.apk` files, which is right for
a release root. For this experiment the pragmatic path is to `apk add` from the network
inside the build container (a build-time action, not something shipped), then strip
`/var/cache/apk` and the resolver state before packing, and pin exact versions once the image
is proven to work. Iterate over **tethered chainload**, and only enroll once it comes up.

## Built (2026-07-25)

```text
initramfs-alpine-dwm.cpio.xz  40073ac9f9fdcc932388efb8a0f1ef3dc1e18d277590ac5dc5d51b73cf35d66e
                              15,657,576 B (14.93 MiB), expands to 65 MiB
m1n1-b0-alpine-dwm.bin        c40b6ed9c439fc4aec804cc2c3e6657add49a7a0fcaa5813b4b87d0fb9fbc0b0
                              21,725,184 B (20.72 MiB) = 1326 x 16 KiB pages
```

Built by `scripts/t6040-build-alpine-dwm.sh`; strict verifier **PASS**. Members: window-free
m1n1 v7 `ecd264a5` (so a tethered chainload smoke is not caught by its own proxy window),
diet kernel `efba5999`, storage-disabled DTB `2782b922`, bootargs `rdinit=/sbin/init`.

### My size projection was wrong by 2.5x, and then the trim beat it

The design section above projected ~25 MiB xz from a 27-package closure. The real install was
**103 packages / 272.7 MiB**, because my dependency resolver deliberately skipped `so:`/`pc:`
virtual dependencies — which is precisely what pulled in the other 76 packages. First build:
65.33 MiB xz, and the verifier **correctly rejected the object** because the initramfs expanded
to 273.7 MiB, over ticket 080's 256 MiB expanded-initramfs policy.

Rather than raise a safety limit to accommodate bloat, I looked at what was actually large:

```text
181 MiB  usr/lib/libLLVM.so.22.1        <- 62% of the image
 36 MiB  usr/lib/libgallium-26.1.1.so
 22 MiB  usr/share/fonts
```

`libLLVM` is Mesa's **llvmpipe JIT**. Checked with `objdump -p` before deleting anything:
`Xorg` links nothing from LLVM/gallium/GL, `modesetting_drv.so` needs only `libgbm.so.1`, and
`dwm`/`st` link no GL at all — LLVM and gallium exist purely for DRI/llvmpipe rendering, which
`AccelMethod "none"` + `AutoAddGPU false` never invokes. So the build now removes libLLVM,
libgallium, SPIRV-Tools, the DRI driver directories, surplus font families, and doc/man trees:

```text
before: 290 MiB   after: 65 MiB      (xz 65.33 MiB -> 14.93 MiB, 4.4x)
```

`st` resolves its default font (`Liberation Mono:pixelsize=12`, confirmed from its strings)
through fontconfig, so `font-liberation` is deliberately kept while dejavu/misc are dropped.

This also revises the design note above: with llvmpipe removed there is **no software GL** in
this image, so `dwl`/Wayland (ticket 144) would need libgallium+libLLVM added back (+217 MiB
installed, still affordable given the 256 MiB object ceiling) or a different renderer.

### Configuration shipped

- `/etc/X11/xorg.conf`: `modesetting` driver, `AccelMethod "none"`, `ShadowFB "true"`,
  `AutoAddGPU false`, `AllowMouseOpenFail true` — the last because the trackpad is still
  unsupported (tickets 004/126) and Xorg must not refuse to start without a pointer.
- `/usr/local/sbin/t6040-startx`: writes `.xinitrc` running `setxkbmap no` (Norwegian layout
  in X, since dwm keybindings are compile-time), `st &`, then `exec dwm`; logs to
  `/var/log/xorg-startx.log`.
- inittab: mounts proc/sys/dev/devpts, loads the Norwegian console keymap via
  `busybox loadkmap`, runs startx once, and keeps a `getty` on tty1 as an escape hatch.

### Not yet booted

Next step is a **tethered chainload smoke over KIS** (not the USB gadget — the gadget cannot
observe a `tty0` console, per the harness rule in
`done/2026-07-25-t6040-ubuntu-untethered-object.md`). Watch for: modesetting probing
`simpledrm`, Xorg starting without a pointer device, dwm appearing on the panel, and whether
the diet kernel's missing `DRM_TTM`/`DRM_SCHED`/`DRM_DISPLAY_HELPER` matter. `xorg-startx.log`
is the first place to look if the panel stays on the console.
