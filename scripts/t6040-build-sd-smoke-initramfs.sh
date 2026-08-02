#!/usr/bin/env bash
# Derive a no-automount GL9755 diagnostic root from the reproducible daily root.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
BASE=${BASE:-$OUT/initramfs-alpine-dwm-i3-everything-no-hidf.cpio.xz}
DEST=${DEST:-$OUT/initramfs-alpine-sd-smoke.cpio.xz}
TMP=$(mktemp -d "$OUT/alpine-sd-smoke.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

[ -f "$BASE" ] || { echo "missing reproducible base initramfs: $BASE" >&2; exit 1; }
LC_ALL=C xz -dc "$BASE" | (cd "$TMP" && LC_ALL=C bsdtar -xf -)

install -m 0755 "$ROOT/scripts/t6040-sd-readonly-smoke.sh" \
	"$TMP/usr/local/sbin/t6040-sd-readonly-smoke"
install -m 0755 "$ROOT/scripts/t6040-sd-write-smoke.sh" \
	"$TMP/usr/local/sbin/t6040-sd-write-smoke"

# Deliberately omit t6040-data-mount: the daily root would mount SD64 rw in a
# background loop before ticket A could assert read-only operation. Also omit
# X, WiFi, USB gadget, and every other unrelated once-task from this root.
cat > "$TMP/etc/inittab" <<'EOF'
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
::sysinit:/bin/mount -t devtmpfs devtmpfs /dev
::sysinit:/bin/mkdir -p /dev/pts /tmp /run /var/log /mnt/sd-ro /mnt/sd-rw
::sysinit:/bin/mount -t devpts devpts /dev/pts
::once:/bin/sh -c 'echo "T6040 SD diagnostic: no automount; run the ticket script explicitly" > /dev/console'
tty1::respawn:/sbin/getty -n -l /bin/sh 38400 tty1 linux
::respawn:/usr/local/sbin/t6040-b0-ttydc0-console
::ctrlaltdel:/sbin/reboot
EOF
ln -sf /bin/busybox "$TMP/init"
ln -sf /bin/busybox "$TMP/sbin/init"

python3 "$ROOT/scripts/reproducible-newc.py" "$TMP" |
	xz -9e --check=crc32 -T1 > "$DEST"

ARCHIVE_LIST=$(xz -dc "$DEST" | cpio -it 2>/dev/null)
for path in ./bin/mount ./bin/umount ./bin/ls ./usr/bin/sha256sum \
	./sbin/blkid ./usr/bin/find ./usr/local/sbin/t6040-sd-readonly-smoke \
	./usr/local/sbin/t6040-sd-write-smoke; do
	grep -qx "$path" <<< "$ARCHIVE_LIST" || {
		echo "missing required initramfs tool: $path" >&2
		exit 1
	}
done
INITTAB=$(xz -dc "$DEST" | bsdtar -xOf - etc/inittab)
[ -n "$INITTAB" ] || { echo "diagnostic inittab is empty or missing" >&2; exit 1; }
if grep -Eq 't6040-data-mount|t6040-data-sync' <<< "$INITTAB"; then
	echo "unsafe SD automount entry survived in the diagnostic root" >&2
	exit 1
fi

echo "initramfs -> $DEST"
shasum -a 256 "$DEST"
