#!/usr/bin/env bash
# t6040-build-usbroot-image.sh — build a bootable Alpine ext4 root IMAGE FILE
# for the "write on the M1, read/boot on the M4" USB-stick path (2026-07-24).
#
# This provisional builder is retained only to make its missing-OpenRC failure
# explicit. Use scripts/t6040-build-usb-root-image.sh after ticket 091 replaces
# its minirootfs userspace with the verified Alpine/OpenRC B0 root.
#
# The M4 boots kernel/DTB/initramfs from the enrolled m1n1 object and mounts this
# stick read-only-then-rw as root (root=LABEL=t6040root rootfstype=ext4). The M4
# never needs to WRITE the stick. NOTE: M4 USB *enumeration* is still gated on the
# ATC-PHY/HPM host-link bring-up (ticket 023 / yuka's tps6598x-spmi); this image
# is ready for the moment that lands. See
# done/2026-07-24-t6040-usb-stick-readwrite-state.md.
set -euo pipefail

MINIROOT="${MINIROOT:-/out/alpine-minirootfs-3.24.0-aarch64.tar.gz}"
OUT_IMG="${OUT_IMG:-/out/t6040-usbroot-alpine.img}"
SIZE_MB="${SIZE_MB:-512}"
LABEL="${LABEL:-t6040root}"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
tar -xzf "$MINIROOT" -C "$stage"

# Alpine minirootfs has a BusyBox /sbin/init and an inittab that invokes
# /sbin/openrc, but does not ship OpenRC. Refuse to create a structurally valid
# ext4 image that cannot complete PID-1 initialization.
[ -x "$stage/sbin/openrc" ] || {
    echo "ERROR: minirootfs lacks /sbin/openrc; external-root image would not boot" >&2
    echo "Use the ticket-091 OpenRC-root replacement when available." >&2
    exit 1
}

echo "wallace-usbroot" > "$stage/etc/hostname"
cat > "$stage/etc/fstab" <<EOF
LABEL=$LABEL / ext4 rw,relatime 0 1
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
EOF
# getty on the DockChannel console (ttydc0) and the internal panel (tty0)
cat > "$stage/etc/inittab" <<EOF
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
ttydc0::respawn:/sbin/getty -L 0 ttydc0 vt100
tty0::respawn:/sbin/getty 0 tty0 linux
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF
# passwordless root: local-console bring-up only, no secret baked in
sed -i 's#^root:[^:]*:#root::#' "$stage/etc/shadow" 2>/dev/null || true
echo "t6040 usb-root alpine 3.24.0 aarch64 (bring-up)" > "$stage/etc/wallace-usbroot"

# optional kernel modules tree for a full root (USB/storage/ext4 are built-in)
[ -n "${MODULES_DIR:-}" ] && cp -a "$MODULES_DIR" "$stage/lib/modules"

[ ! -e "$OUT_IMG" ] || {
    echo "ERROR: refusing to overwrite $OUT_IMG" >&2
    exit 1
}
mke2fs -q -t ext4 -L "$LABEL" -d "$stage" -F "$OUT_IMG" "${SIZE_MB}M"

echo "built $OUT_IMG"
dumpe2fs -h "$OUT_IMG" 2>/dev/null | grep -iE 'volume name|Filesystem UUID'
sha256sum "$OUT_IMG"
