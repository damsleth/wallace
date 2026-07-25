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
