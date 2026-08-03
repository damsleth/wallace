# T6040 Ubuntu 24.04 RAM-root boot — distro progression complete (2026-07-24)

The distro-complexity progression the mission called for — **busybox → alpine →
ubuntu** — is complete: Ubuntu 24.04 (glibc) userland now boots on the M4.

## What was built

`initramfs-ubuntu-ramroot.cpio.gz` (SHA-256
`94753f886a4d0551e1baafe7d0555daf1a26ff75f826084890581bc035cef588`, 28 MB) from
the official `ubuntu-base-24.04.3-base-arm64.tar.gz`
(SHA-256 `7b2dced6…`, fetched host-side) + a custom `/init` (1488 B): mounts
proc/sys/dev/run/tmp, feeds `/dev/watchdog0` (shell ping loop, no busybox needed —
Ubuntu has util-linux/bash), prints os-release/uname/libc/partitions/input
inventory, then spawns an interactive `/bin/bash` login on `/dev/ttydc0`.

Unlike the Alpine *minirootfs* (which lacks `/sbin/openrc` — Sol's catch, would
hang PID1), ubuntu-base is a **self-contained glibc rootfs with a working init**,
so the RAM-root boots as-is with a minimal custom `/init`.

## Live result

Boot set: m1n1 upper-guard `1394c345` + `Image-hid-type-fix` `df7657c1` (the
keyboard-fixed dcuart kernel) + DTB `2782b922` + the Ubuntu initramfs; maxcpus=1,
no `root=` (RAM-root), console over ttydc0. Lease held+released healthy.
`logs/t6040-console-20260724-ubuntu-ramroot.log`:

```
*** Ubuntu 24.04 RAM-root on /dev/ttydc0 (glibc) ***
[?2004h ]0;root@(none): /
root@(none):/#
```

Ubuntu's **glibc bash reached an interactive prompt** (the `[?2004h`
bracketed-paste + `]0;…` title escape are bash's interactive-shell setup, not
busybox/musl) on the M4. Machine stable through the boot — watchdog fed, no
reset/panic. (The os-release/uname diagnostics went to the kernel console
`tty0`, not remotely visible; the ttydc0 banner + bash prompt are the proof. The
ttydc0 *console RX* is still the separate poll-mode-console limitation, so typed
input isn't echoed remotely — but the internal keyboard `event0` works, per the
078 fix in this same kernel.)

## Significance

- **All three target distros boot untethered-capable on the M4**: BusyBox
  (initramfs), Alpine (RAM-root), Ubuntu 24.04 (RAM-root, glibc). This is the
  distro-progression milestone.
- Proves the M4 bring-up carries a **full glibc/systemd-class distro's userland**
  (dpkg/apt/bash/coreutils present in the image), not just musl minimalism.
- RAM-root (no storage) is the vehicle; a persistent Ubuntu on USB awaits the
  M4 USB-enumeration unblock (ATC/HPM, ticket 023 / Sol) — at which point the
  same ubuntu-base populates a persistent ext4 root (ticket 086 GPT image flow).

## Refinements (2026-07-24, both re-booted clean)

CJ, watching the M4 **panel** (confirming fbcon on the internal display works),
flagged two things:

1. **`watchdog: watchdog0: watchdog did not stop!`** — the first init pinged the
   watchdog with `echo 1 > /dev/watchdog0` in a loop, which *opens and closes* the
   device each iteration; on every close the framework tries to stop apple_wdt,
   can't, and warns. Non-fatal (the write still pinged it; timeout > 10 s interval,
   so it survived) but noisy. **Fixed**: hold one fd open —
   `( exec 8>/dev/watchdog0; while true; do echo 1 >&8; sleep 10; done ) &` — no
   per-ping close, no warning.
2. **Norwegian keyboard** — CJ's J614s is Norwegian, so the panel console needs the
   Norwegian keymap. Injected `loadkeys` (Ubuntu `kbd`) + the Debian `console-data`
   keymaps and added `loadkeys no-latin1 || loadkeys no` to the init.

Final image: `initramfs-ubuntu-ramroot-no.cpio.gz` SHA-256
`0987cb7c22cabe2c4fdd5f25544441733452bee0b2b605b5c20b9275298323fa` (29 MB) —
watchdog-fix **and** Norwegian keymap. Re-booted clean to `root@(none):/#`
(`logs/t6040-console-20260724-ubuntu-no.log`); the `loadkeys`/watchdog output
goes to `tty0` (the panel), which CJ observes. See memory `norwegian-keyboard`:
apply `loadkeys no` + `nb_NO` to all future boot images.

## Reproduce
`ubuntu-base-arm64.tar.gz` in `linux-build-out/`; build the initramfs by
extracting it to a stage dir, adding the `/init` above, injecting `kbd`'s
`loadkeys` + `console-data` `no*.kmap.gz` for the Norwegian keymap, then
`find . | cpio -o -H newc | gzip -9`. Kernel = any current dcuart build (carries
the HID-type fix via kbuild). Ticket 091 done.
