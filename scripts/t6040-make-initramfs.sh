#!/usr/bin/env bash
# Replace /init in the known-good proof initramfs with the persistent-shell init.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
BASE=${BASE:-$OUT/initramfs.cpio.gz}
DEST=${DEST:-$OUT/initramfs-dcuart.cpio.gz}
INIT_SOURCE=${INIT_SOURCE:-$ROOT/scripts/t6040-init-dcuart}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

LC_ALL=C gzip -dc "$BASE" | (cd "$TMP" && LC_ALL=C bsdtar -xf -)
install -m 0755 "$INIT_SOURCE" "$TMP/init"

# Optional paired Apple trackpad firmware, produced by asahi-fwextract.
# Example: TRACKPAD_FIRMWARE=/path/to/tpmtfw-j614s.bin ./scripts/t6040-make-initramfs.sh
if [ -n "${TRACKPAD_FIRMWARE:-}" ]; then
    python3 - "$TRACKPAD_FIRMWARE" <<'PY'
import pathlib
import struct
import sys

path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 20:
    raise SystemExit(f"{path}: truncated HIDF header ({len(data)} bytes)")

magic, version, header_length, data_length, iface_offset = \
    struct.unpack_from("<4sIIII", data)
if magic != b"HIDF" or version != 1:
    raise SystemExit(f"{path}: not a version-1 HIDF trackpad image")
if header_length < 20 or header_length > len(data):
    raise SystemExit(f"{path}: invalid HIDF header length {header_length}")
if data_length > len(data) - header_length:
    raise SystemExit(f"{path}: truncated HIDF payload ({data_length} bytes declared)")
if iface_offset >= data_length:
    raise SystemExit(f"{path}: HID interface offset is outside the payload")

print(f"trackpad HIDF OK: {data_length} payload bytes, interface offset {iface_offset}")
PY
    install -d "$TMP/lib/firmware/apple"
    install -m 0644 "$TRACKPAD_FIRMWARE" \
        "$TMP/lib/firmware/apple/tpmtfw-j614s.bin"
fi

# Optional paired BCM4388 WiFi/BT firmware staged by ticket 014
# (done/2026-07-14-t6040-bcm4388-fw-extract.md). Points at a vendorfw/ tree
# holding brcm/ files in Linux firmware naming; installs only the apple,mriya
# board set. Example: VENDORFW_DIR=/private/tmp/t6040-vendorfw/vendorfw \
#   ./scripts/t6040-make-initramfs.sh
if [ -n "${VENDORFW_DIR:-}" ]; then
    if ! compgen -G "$VENDORFW_DIR/brcm/*apple,mriya*" >/dev/null; then
        echo "VENDORFW_DIR=$VENDORFW_DIR has no brcm/*apple,mriya* files" >&2
        exit 1
    fi
    install -d "$TMP/lib/firmware/brcm"
    n=0
    for f in "$VENDORFW_DIR"/brcm/*apple,mriya*; do
        install -m 0644 "$f" "$TMP/lib/firmware/brcm/$(basename "$f")"
        n=$((n + 1))
    done
    echo "installed $n apple,mriya wireless firmware files"
fi

# Optional space-separated EXTRA_FILES="src:dest src:dest" copied into the image.
for pair in ${EXTRA_FILES:-}; do
    src=${pair%%:*}; dest=${pair#*:}
    mkdir -p "$TMP/$(dirname "$dest")"
    install -m 0644 "$src" "$TMP/$dest"
done

(cd "$TMP" && LC_ALL=C find . -print | LC_ALL=C sort | \
    LC_ALL=C cpio -o -H newc 2>/dev/null | gzip -9) >"$DEST"

echo "initramfs -> $DEST"
shasum -a 256 "$DEST"
