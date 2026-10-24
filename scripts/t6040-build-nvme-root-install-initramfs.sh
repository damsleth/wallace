#!/usr/bin/env bash
# Pack the ticket-5005 one-shot NVMe root installer: the pinned Alpine
# bootstrap (BusyBox 1.37, e2fsprogs 1.47.4) with /init replaced by
# scripts/t6040-init-nvme-root-install. Deterministic; never touches a device.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
BASE=${BASE:-$OUT/initramfs-bootstrap-sdroot.cpio.gz}
DEST=${DEST:?set DEST to the output .cpio.gz}
BASE_SHA256=ae815319e2d6d4b76cdfda09dd23b94f30908950907b1f8284192e637f82a097
FSCK=${FSCK:-$OUT/fsck.exfat}
FSCK_SHA256=d56b877d91e8e42a64cf8d8ad574ea425041f6fe117f0e52180f84ffad972790
KEYMAP=${KEYMAP:-$OUT/no-latin1.bmap}
KEYMAP_SHA256=606ecd98f83b72983f3cd35976df939dc9c7187283703736a81e89b65aee85a8
[ ! -e "$DEST" ] || { echo "refusing to overwrite $DEST" >&2; exit 1; }
printf '%s  %s\n' "$BASE_SHA256" "$BASE" "$FSCK_SHA256" "$FSCK" "$KEYMAP_SHA256" "$KEYMAP" |
    shasum -a 256 -c -
TMP=$(mktemp -d "$OUT/nvme-root-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

LC_ALL=C gzip -dc "$BASE" | (cd "$TMP" && LC_ALL=C bsdtar -xf -)
install -m 0755 "$ROOT/scripts/t6040-init-nvme-root-install" "$TMP/init"
install -d -m 0755 "$TMP/sbin" "$TMP/etc"
install -m 0755 "$FSCK" "$TMP/sbin/fsck.exfat"
install -m 0644 "$KEYMAP" "$TMP/etc/wallace-no.bmap"
# Nothing here may create a filesystem, partition, discard or erase. Only the
# e2fsprogs the installer calls stay: e2fsck, tune2fs, resize2fs, dumpe2fs.
rm -rf "$TMP/etc/wpa_supplicant" "$TMP/root/.ssh" "$TMP/var/cache/apk/"*
rm -f "$TMP"/etc/ssh/ssh_host_* "$TMP/var/log/apk.log" \
    "$TMP"/sbin/{mke2fs,mkfs.ext2,mkfs.ext3,mkfs.ext4,mkfs.vfat,mkdosfs,mkswap,fdisk,blkdiscard,fstrim} \
    "$TMP"/usr/sbin/{badblocks,debugfs,e2image,e2undo,e4crypt,e4defrag,mklost+found,partprobe,nandwrite,setpci,mkfs.exfat,tune.exfat,exfatlabel,exfat2img}
for f in init sbin/fsck.exfat sbin/e2fsck usr/sbin/tune2fs usr/sbin/resize2fs usr/sbin/dumpe2fs \
         etc/wallace-no.bmap bin/busybox lib/ld-musl-aarch64.so.1; do
    [ -e "$TMP/$f" ] || { echo "missing installer member: $f" >&2; exit 1; }
done
for f in sbin/mke2fs sbin/mkfs.ext4 sbin/blkdiscard sbin/fdisk usr/sbin/debugfs; do
    [ ! -e "$TMP/$f" ] || { echo "forbidden installer member: $f" >&2; exit 1; }
done
python3 "$ROOT/scripts/reproducible-newc.py" "$TMP" | gzip -n -9 >"$DEST"
shasum -a 256 "$DEST"
