# T6040 Alpine RAM-root artifact (2026-07-23)

Offline ticket 066. This is the storage-free fallback after ticket 065 was
cancelled unrun because the powered hub's supply was unavailable.

The result is a real Alpine aarch64 userspace delivered as the kernel
initramfs. It lives entirely in RAM and needs neither the right-side USB port
nor internal NVMe.

## Source and reproducible build

The builder pins Alpine 3.24.0's official aarch64 minirootfs:

- source:
  `https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/alpine-minirootfs-3.24.0-aarch64.tar.gz`
- upstream SHA-256:
  `4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a`
- cached source size: 4,043,766 bytes

Build:

```sh
scripts/t6040-build-alpine-ramroot.sh
```

The script verifies the pinned source checksum, extracts it into a new
`mktemp` directory, installs the Wallace `/init`, rejects block-device nodes,
normalizes timestamps, and uses GNU cpio in the existing `kbuild` container
with `--owner=0:0 --reproducible`, followed by `gzip -n -9`.

Two consecutive clean builds produced the identical output hash:

| Artifact | SHA-256 |
|---|---|
| `scripts/t6040-init-alpine-ramroot` | `1ba4eaf9fa1654fe52ba1f11ae00377136284a46644ebd1fd9199e87f0fc9fff` |
| `scripts/t6040-build-alpine-ramroot.sh` | `d1e2921db7c994f00d19d04c269144fffd82399c1a9cb101f98bc4bc8146fe11` |
| `linux-build-out/initramfs-alpine-ramroot.cpio.gz` | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |
| `linux-build-out/initramfs-alpine-ramroot.contents` | `eb4f3802eafe11ac9cf630ac250d7f9c12193f592fea323052c5d60e68b3e9f8` |

The result is 4,041,821 bytes compressed and 8,765,952 bytes as newc, with
516 inventory entries.

## Runtime behavior

The custom `/init`:

- mounts only `proc`, `sysfs`, `devtmpfs`, and RAM-backed `tmpfs` on `/run`
  and `/tmp`;
- starts the already proven watchdog keepalive when `/dev/watchdog0` exists;
- waits for `/dev/ttydc0`, holds it open, and respawns an interactive Alpine
  root shell there;
- leaves a framebuffer/keyboard shell as fallback;
- performs no block discovery, `mdev`, `modprobe`, filesystem mount, network
  setup, or package installation.

There is no `switch_root`, `/newroot`, `root=`, or reference to `/dev/sd*` or
`/dev/nvme*`. Writes made in the shell affect the RAM-backed initramfs/tmpfs
only and disappear on reboot.

## Host validation

The generated cpio records root ownership and fixed timestamps. Its required
entries are present:

- `/init`
- `/bin/busybox`
- `/etc/alpine-release`
- `/lib/ld-musl-aarch64.so.1`

The archive was unpacked inside the native arm64 `kbuild` container and
chroot-tested:

```text
/etc/alpine-release = 3.24.0
apk --print-arch = aarch64
/bin/sh -n /init = PASS
mount, watchdog, setsid = present
ALPINE_CHROOT_OK
```

The selected kernel config has `CONFIG_BLK_DEV_INITRD`, `CONFIG_RD_GZIP`,
`CONFIG_DEVTMPFS`, `CONFIG_DEVTMPFS_MOUNT`, and `CONFIG_TMPFS` built in.

## Intended boot pair

The proposed first run reuses the ticket-063 live-proven m1n1 and kernel but
switches back to the standard USB-disabled J614s DT:

| Input | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-usb-host` | `6f0daf57baf942d6e1f43d8efa2ebd4160e976c02ccfaad232dd42e918eb7482` |
| `t6040-j614s-dcuart.dtb` | `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814` |
| `initramfs-alpine-ramroot.cpio.gz` | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |
| `config-usb-host` | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

The kernel contains the experimental USB host support, but the selected
standard DT keeps all three DWC3 controllers and their DARTs disabled. Its ANS,
SART, and internal NVMe nodes are also disabled. Decompiled inspection found
no `apple,force-host-mode`; DockChannel remains in the proven poll mode.
Post-run re-decompilation corrected the preflight record: this exact pinned
standard DTB still contains stale ADT IRQ 360, not measured IRQ 816. The driver
does not acquire that interrupt in `apple,poll-mode`, so the cell was inert in
ticket 067. Future builds use the corrected source and must encode 816.

Exact proposed live procedure and pass/stop conditions:
`done/2026-07-23-t6040-alpine-ramroot-preflight.md`.
