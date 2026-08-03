#!/usr/bin/env bash
# Rebuild the hardened ticket-204 switch-root initramfs deterministically.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
BASE=${BASE:-$OUT/initramfs-sdroot-base-9d5cd5c4.cpio.gz}
DEST=${DEST:-$OUT/initramfs-sdroot-hardened.cpio.gz}
BASE_SHA256=9d5cd5c48ae22b74261be90ee2ee2db15da24943659d656404a546fc3b7fdfba
TMP=$(mktemp -d "$OUT/sdroot-initramfs.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

[ -f "$BASE" ] || { echo "missing pinned base: $BASE" >&2; exit 1; }
printf '%s  %s\n' "$BASE_SHA256" "$BASE" | shasum -a 256 -c -

LC_ALL=C gzip -dc "$BASE" | (cd "$TMP" && LC_ALL=C bsdtar -xf -)
install -m 0755 "$ROOT/scripts/t6040-sdroot-init" "$TMP/init"
install -m 0755 "$ROOT/scripts/t6040-sdroot-shutdown" "$TMP/shutdown"

python3 "$ROOT/scripts/reproducible-newc.py" "$TMP" | gzip -n -9 >"$DEST"

for item in init shutdown bin/busybox; do
    gzip -dc "$DEST" | cpio -it 2>/dev/null | grep -qx "./$item" || {
        echo "missing initramfs member: $item" >&2
        exit 1
    }
done

for item in init shutdown; do
    embedded=$(gzip -dc "$DEST" | bsdtar -xOf - "$item" | shasum -a 256 | awk '{print $1}')
    source=$(shasum -a 256 "$ROOT/scripts/t6040-sdroot-$item" | awk '{print $1}')
    [ "$embedded" = "$source" ] || { echo "$item hash mismatch" >&2; exit 1; }
done

echo "initramfs -> $DEST"
shasum -a 256 "$DEST"
