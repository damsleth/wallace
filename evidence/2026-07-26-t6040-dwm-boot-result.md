# Ticket 148 RESULT: dwm did not start — the diet kernel has no AF_UNIX (FAIL, root-caused)

Object `m1n1-b0-alpine-dwm.bin` `c40b6ed9` ran correctly (`Loading kernel image (0x14b8004)` =
21,725,184 + 4) and m1n1 handed off cleanly (`Valid payload found` → `Vectoring to next stage`,
`display: Hiding notch, 3024x1964 -> 3024x1890`). Linux booted, the internal keyboard came up on
`event0`, and the tty1 getty escape hatch worked. **Xorg then failed fatally and dwm never started.**

## Root cause: no UNIX-domain sockets in the kernel

`/var/log/xorg-startx.log`:

```
_XSERVTransSocketOpenCOTSServer: Unable to open socket for local
_XSERVTransOpen: transport open failed for local/(none):0
_XSERVTransSocketOpenCOTSServer: Unable to open socket for unix
Fatal server error:
(EE) Cannot establish any listening sockets - Make sure an X server isn't already running
xinit: unable to connect to X server: Function not implemented
```

`Function not implemented` is **ENOSYS**. `config-b0-diet` contains:

```
# CONFIG_NET is not set
```

and `CONFIG_UNIX` is therefore absent entirely (it depends on `NET`). X11 requires an **AF_UNIX**
listening socket for local clients, so `socket(AF_UNIX, …)` cannot succeed and the server dies before
it ever touches the display.

**Neither failure mode ticket 148 predicted was involved.** It warned about `modesetting` failing to
probe simpledrm and about Xorg refusing to start without a pointer; both are downstream of socket
creation, which is where this died. The `xauth … bad display name "(none):0"` lines are a
consequence, not a cause.

This is a **direct casualty of kernel stripping**: DIET dropped `CONFIG_NET` to save a few MiB of a
33 MiB kernel and thereby removed a hard requirement of every X server.

## Second, independent defect: the Norwegian keymap file name

Boot console: `/bin/sh: can't open /usr/share/bkeymaps/no/no-mac.bmap: no such file`.

The dwm image ships `kbd-bkeymaps` as installed — **gzipped**:

```
./usr/share/bkeymaps/no/no-mac.bmap.gz
```

while the proven B0 image has it **uncompressed** (`no/no-mac.bmap`), which is what both the inittab
line and `scripts/t6040-b0-keymap.initd` read. So the console keymap silently did not load (the
`|| true` kept boot going). `setxkbmap no` never ran either, since X never started — so this image
had **no** Norwegian layout by either path, violating the standing keyboard preference.

Fixed in `scripts/t6040-build-alpine-dwm.sh`: try `.bmap`, then `zcat` the `.bmap.gz`, for both
`no-mac` and `no`.

## The bigger conclusion: stop trimming these images

The trimming was justified by an assumed size ceiling that does not exist. Measured facts:

- **no object-size ceiling was found up to 256 MiB** (ticket 137) — and 256 MiB was the *probe*
  limit and the verifier's *policy* number, not a hardware limit;
- RAM is ~23 GiB, so the unpacked root is nowhere near binding;
- the only real costs of a big payload are single-threaded xz decompress time (minilzlib requires a
  single stream/single block, `-T1`) and boot latency — both modest and non-binding at our scale.

Against that, trimming has now cost real progress twice over in one image:

1. `libLLVM`/llvmpipe was cut (290 → 65 MiB) purely to fit the assumed ceiling, removing **software
   GL** from the one image whose entire purpose is graphical;
2. `CONFIG_NET` was cut from the kernel, which **fatally broke X**.

So the policy should inverse: **build for capability and only shrink if something actually
overflows.** Filed as ticket **155** (rebuild the graphical image on a full-featured kernel, restore
llvmpipe) and **156** (measure the real ceiling above 256 MiB, so the number is known rather than
assumed).

## Honest caveat on the fix

`DIET_CAPABLE` does enable `-e UNIX -e NET -e INET -e PACKET -e SYSVIPC`, and 147 just cleared it, so
it is the quickest path past this failure. But DIET still drops `DRM_TTM`/`DRM_SCHED`/
`DRM_DISPLAY_HELPER`, which `DIET_CAPABLE` does **not** re-add — so fixing AF_UNIX may simply advance
to the simpledrm/modesetting probe failure 148 originally predicted. That is the argument for going
to a full kernel rather than adding symbols one failure at a time.
