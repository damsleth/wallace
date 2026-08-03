# Ticket 153: diagnostic dual-console object — built, strict-verified

`m1n1-b0-dwm-fat-diag.bin` `d14df9f3644893245d518f2396687387740b782225f3975f84c623e6cf9a59b3`
**83,197,952 B = 5078 × 16 KiB**, strict verify **PASS**, kernel `pages=4K`.

Byte-for-byte the fat graphical object (ticket 155) except the bootargs, which add `console=ttydc0`:

```
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 console=ttydc0 fbcon=font:TER16x32 ignore_loglevel rdinit=/sbin/init
```

bootargs hash `68198332…` — **deliberately different** from the proven `3659a0da…`. Every member
hash is identical to `m1n1-b0-dwm-fat.bin` (`c5438779`), so the two objects differ *only* in the
console setting.

## Why this exists

Twice on 2026-07-26 a rig run could not be judged from the host: the proven bootargs use
`console=tty0` only, so the kernel's own dmesg never reaches the KIS pty. In the 147 run the log had
no `Kernel command line` and no driver output; in the 148 dwm run the pty went silent at handoff and
the post-handoff console log was **0 bytes**, so the maintainer's screenshot of
`/var/log/xorg-startx.log` was the only evidence. This object makes the machine report its own dmesg.

## Transport is viable, checked not assumed

- the DTB `2782b922` has a `serial { compatible = "apple,dockchannel-serial"; }` node with **no
  `status` property**, so it defaults to enabled;
- there is **no `stdout-path`** in `chosen`, so `console=ttydc0` on the cmdline is precisely what
  selects it — it is not a no-op and not a duplicate;
- the parent dockchannel node carries `apple,poll-mode`, the conservative live-proven path;
- KIS *can* observe `ttydc0` — it is the **USB gadget** that cannot, since gadget and DebugUSB/KIS
  are mutually exclusive on the DFU port. This smoke is over KIS, so the arrangement is correct.

## Expectations

- **Expect a slow boot, and do not read it as a hang.** Two compounding costs: 67 MiB of
  single-threaded xz (minilzlib requires single-stream/single-block), and then `ignore_loglevel`
  pushing the entire verbose dmesg through a *polled* dockchannel console. `ignore_loglevel` was kept
  deliberately — detail is the whole point of this variant.
- `/dev/console` becomes the **last** `console=` given, i.e. `ttydc0`. The inittab spawns its getty on
  `tty1` explicitly and X starts via `startx -- vt1 -keeptty`, so the panel session is unaffected.
- **Diagnostic only.** Its bootargs are not the proven set, so any result from it must be labelled as
  such, and enrollment/acceptance runs keep `m1n1-b0-dwm-fat.bin`.

## Run it

```sh
bash scripts/t6040-debugusb-console.sh reboot
bash scripts/t6040-boot-raw-object.sh \
    ~/Code/linux-build-out/m1n1-b0-dwm-fat-diag.bin \
    d14df9f3644893245d518f2396687387740b782225f3975f84c623e6cf9a59b3
```

With ticket 151's verdict logic also in place, this pairing is what makes a graphical smoke
self-verifying: a correct verdict line plus readable kernel evidence in `raw-object-chainload.log`.
