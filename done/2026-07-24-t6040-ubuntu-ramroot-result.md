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

## Reproduce
`ubuntu-base-arm64.tar.gz` in `linux-build-out/`; build the initramfs by
extracting it to a stage dir, adding the `/init` above (see this file / the
git history), `find . | cpio -o -H newc | gzip -9`. Kernel = any current dcuart
build (carries the HID-type fix via kbuild). Ticket 091 done.
