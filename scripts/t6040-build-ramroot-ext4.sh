#!/usr/bin/env bash
# Build a 64 MiB ext4 root image for the root=/dev/ram0 rehearsal (ticket 145).
#
# Purpose: exercise the REAL root path — root=, a genuine block device, fstab, OpenRC on
# a mounted filesystem, e2fsck — before USB storage exists, so that when enumeration
# lands (096/097/128) the software side is already proven. m1n1 carries the image via its
# m1n1_initramfs wrapper (load_cpio does no content validation), and CONFIG_BLK_DEV_RAM
# loads a non-cpio initrd into /dev/ram0.
set -euo pipefail

OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
CONTAINER=${CONTAINER:-kbuild}
SRC_INITRAMFS=${SRC_INITRAMFS:-$OUT/initramfs-alpine-b0-nb2.cpio.xz}   # proven B0 userland
IMG=${IMG:-$OUT/ramroot-alpine-b0.ext4}
SIZE_MB=${SIZE_MB:-64}

[ -f "$SRC_INITRAMFS" ] || { echo "missing $SRC_INITRAMFS" >&2; exit 1; }
[ -e "$IMG" ] && { echo "refusing to overwrite $IMG" >&2; exit 1; }

STAGE=$(mktemp -d "$OUT/ramroot.XXXXXX")
STAGE_BASE=$(basename "$STAGE")
trap 'podman exec "$CONTAINER" rm -rf "/out/$STAGE_BASE" >/dev/null 2>&1 || true' EXIT

echo "== unpacking the proven B0 root =="
xz -dc "$SRC_INITRAMFS" | ( cd "$STAGE" && cpio -idm --quiet 2>/dev/null )

# A real root needs an fstab and a writable filesystem, unlike the RAM-root initramfs.
cat > "$STAGE/etc/fstab" <<'EOF'
/dev/ram0   /        ext4     rw,relatime  0 1
proc        /proc    proc     defaults     0 0
sysfs       /sys     sysfs    defaults     0 0
devtmpfs    /dev     devtmpfs defaults     0 0
devpts      /dev/pts devpts   defaults     0 0
tmpfs       /tmp     tmpfs    defaults     0 0
EOF
printf 'wallace-ramroot-ext4\n' > "$STAGE/etc/hostname"
printf 'root=/dev/ram0 ext4 rehearsal for the eventual USB root (ticket 145)\n' \
    > "$STAGE/etc/wallace-ramroot"

# Prove the block/fs layer really is live, not a tmpfs pretending to be a disk.
cat > "$STAGE/usr/local/sbin/t6040-root-report" <<'EOF'
#!/bin/sh
echo "=== t6040 ext4 root report begin ==="
echo "-- root device --";     awk '$2=="/" {print $1, $3}' /proc/mounts
echo "-- block devices --";   cat /proc/partitions
echo "-- writable? --";       ( : > /root/.wtest && echo "root is WRITABLE" && rm -f /root/.wtest ) || echo "root is READ-ONLY"
echo "-- ext4 in use? --";    grep -q ' ext4 ' /proc/mounts && echo "ext4 mounted" || echo "ext4 NOT mounted"
echo "-- keymap --";          cat /run/wallace-keymap-status 2>/dev/null || echo unknown
echo "=== t6040 ext4 root report end ==="
EOF
chmod 0755 "$STAGE/usr/local/sbin/t6040-root-report"
install -d "$STAGE/etc/runlevels/default"
cat > "$STAGE/etc/init.d/t6040-root-report" <<'EOF'
#!/sbin/openrc-run
description="Report the ext4 root state"
depend() { need localmount; }
start() { ebegin "ext4 root report"; /usr/local/sbin/t6040-root-report > /dev/console 2>&1; eend 0; }
EOF
chmod 0755 "$STAGE/etc/init.d/t6040-root-report"
ln -sf /etc/init.d/t6040-root-report "$STAGE/etc/runlevels/default/t6040-root-report"

echo "== creating the ext4 image (${SIZE_MB} MiB) =="
podman exec "$CONTAINER" sh -ec "
    mke2fs -q -t ext4 -L t6040root -d '/out/$STAGE_BASE' -F '/out/$(basename "$IMG")' ${SIZE_MB}M
    e2fsck -fn '/out/$(basename "$IMG")' >/dev/null && echo '  e2fsck: clean'
    dumpe2fs -h '/out/$(basename "$IMG")' 2>/dev/null | grep -iE 'volume name|filesystem uuid|block count'
"
python3 - "$IMG" <<'PY'
import hashlib, os, sys
p = sys.argv[1]; d = open(p,'rb').read()
print(f"  {p}: {len(d):,} B ({len(d)/1048576:.0f} MiB)  sha256 {hashlib.sha256(d).hexdigest()}")
PY
