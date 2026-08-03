#!/usr/bin/env bash
# Add pinned exfatprogs and the fail-closed ticket-215 repair script to the
# pinned bootstrap image, then pack it deterministically.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
CONTAINER=${CONTAINER:-kbuild}
BASE=${BASE:-$OUT/initramfs-bootstrap-sdroot.cpio.gz}
DEST=${DEST:-$OUT/initramfs-bootstrap-sdroot-fsck.cpio.gz}
APK=${APK:-$OUT/sdroot-fsck-apks/exfatprogs-1.4.1-r0.apk}
BASE_SHA256=ae815319e2d6d4b76cdfda09dd23b94f30908950907b1f8284192e637f82a097
APK_SHA256=434d1baa4d58ae4a7d5b61de3e24a371c38735a46ec999c2d047a011fd0a2e64
TMP=$(mktemp -d "$OUT/sdroot-fsck.XXXXXX")
TMP_BASE=${TMP##*/}
trap 'podman exec "$CONTAINER" rm -rf "/out/$TMP_BASE" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

printf '%s  %s\n' "$BASE_SHA256" "$BASE" | shasum -a 256 -c -
printf '%s  %s\n' "$APK_SHA256" "$APK" | shasum -a 256 -c -
LC_ALL=C gzip -dc "$BASE" | (cd "$TMP" && LC_ALL=C bsdtar -xf -)
install -d "$TMP/tmp/sdroot-apks" "$TMP/usr/local/sbin"
install -m 0644 "$APK" "$TMP/tmp/sdroot-apks/"

podman exec "$CONTAINER" chroot "/out/$TMP_BASE" /sbin/apk add \
    --no-network --allow-untrusted /tmp/sdroot-apks/exfatprogs-1.4.1-r0.apk
install -m 0755 "$ROOT/scripts/t6040-sdroot-fsck.sh" \
    "$TMP/usr/local/sbin/t6040-sdroot-fsck"
podman exec "$CONTAINER" sh -c \
    "rm -rf '/out/$TMP_BASE/tmp/sdroot-apks' '/out/$TMP_BASE/var/cache/apk/'*; \
     rm -f '/out/$TMP_BASE/var/log/apk.log' \
       '/out/$TMP_BASE/sbin/blkdiscard' \
       '/out/$TMP_BASE/sbin/blockdev' \
       '/out/$TMP_BASE/sbin/fdisk' \
       '/out/$TMP_BASE/sbin/fstrim' \
       '/out/$TMP_BASE/sbin/mkdosfs' \
       '/out/$TMP_BASE/sbin/mke2fs' \
       '/out/$TMP_BASE/sbin/mkfs.ext2' \
       '/out/$TMP_BASE/sbin/mkfs.ext3' \
       '/out/$TMP_BASE/sbin/mkfs.ext4' \
       '/out/$TMP_BASE/sbin/mkfs.vfat' \
       '/out/$TMP_BASE/sbin/mkswap' \
       '/out/$TMP_BASE/usr/sbin/badblocks' \
       '/out/$TMP_BASE/usr/sbin/debugfs' \
       '/out/$TMP_BASE/usr/sbin/e2image' \
       '/out/$TMP_BASE/usr/sbin/e2label' \
       '/out/$TMP_BASE/usr/sbin/e2undo' \
       '/out/$TMP_BASE/usr/sbin/e4crypt' \
       '/out/$TMP_BASE/usr/sbin/e4defrag' \
       '/out/$TMP_BASE/usr/sbin/mklost+found' \
       '/out/$TMP_BASE/usr/sbin/nandwrite' \
       '/out/$TMP_BASE/usr/sbin/partprobe' \
       '/out/$TMP_BASE/usr/sbin/resize2fs' \
       '/out/$TMP_BASE/usr/sbin/setpci' \
       '/out/$TMP_BASE/usr/sbin/tune2fs' \
       '/out/$TMP_BASE/usr/sbin/mkfs.exfat' \
       '/out/$TMP_BASE/usr/sbin/exfatlabel' \
       '/out/$TMP_BASE/usr/sbin/tune.exfat' \
       '/out/$TMP_BASE/usr/sbin/exfat2img' \
       '/out/$TMP_BASE/usr/sbin/dump.exfat'"

python3 "$ROOT/scripts/reproducible-newc.py" "$TMP" | gzip -n -9 >"$DEST"
for item in usr/sbin/fsck.exfat sbin/e2fsck usr/local/sbin/t6040-sdroot-fsck; do
    gzip -dc "$DEST" | cpio -it 2>/dev/null | grep -qx "./$item" || {
        echo "missing repair-image member: $item" >&2
        exit 1
    }
done
if gzip -dc "$DEST" | cpio -it 2>/dev/null | grep -Eq \
        '^\./(sbin/(blkdiscard|blockdev|fdisk|fstrim|mkdosfs|mke2fs|mkfs\.(ext2|ext3|ext4|vfat)|mkswap)|usr/sbin/(badblocks|debugfs|e2image|e2label|e2undo|e4crypt|e4defrag|mklost\+found|nandwrite|partprobe|resize2fs|setpci|tune2fs|mkfs\.exfat|exfatlabel|tune\.exfat|exfat2img|dump\.exfat))$'; then
    echo "repair image contains an out-of-scope storage mutation tool" >&2
    exit 1
fi

echo "repair initramfs -> $DEST"
shasum -a 256 "$DEST"
