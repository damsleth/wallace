#!/usr/bin/env bash
# Build the storage-free fault-205 characterisation initramfs (ticket 217)
# deterministically from hash-pinned pieces only. Host-only; no target access.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
DEST=${DEST:-$OUT/initramfs-cow-report.cpio.gz}
# BusyBox 1.35 static, as carried by the reviewed SD-root initramfs.
BB_SOURCE=${BB_SOURCE:-$OUT/initramfs-sdroot-daily-v3.build1.cpio.gz}
BB_SHA256=61781806ad3650b0b9d2b3fc6971e2bffdca967af1a95375abd0578bafff14fb
KEYMAP=${KEYMAP:-$OUT/no-latin1.bmap}
KEYMAP_SHA256=606ecd98f83b72983f3cd35976df939dc9c7187283703736a81e89b65aee85a8
TMP=$(mktemp -d "$OUT/cow-report-initramfs.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

install -d -m 0755 "$TMP/bin" "$TMP/etc" "$TMP/proc" "$TMP/sys" "$TMP/dev" "$TMP/usr/local/bin"
LC_ALL=C gzip -dc "$BB_SOURCE" | (cd "$TMP" && LC_ALL=C bsdtar -xf - ./bin/busybox)
printf '%s  %s\n' "$BB_SHA256" "$TMP/bin/busybox" | shasum -a 256 -c -
printf '%s  %s\n' "$KEYMAP_SHA256" "$KEYMAP" | shasum -a 256 -c -
install -m 0644 "$KEYMAP" "$TMP/etc/wallace-no.bmap"
install -m 0755 "$ROOT/scripts/t6040-init-cow-report" "$TMP/init"
install -m 0755 "$ROOT/scripts/t6040-cow-repro.sh" "$TMP/usr/local/bin/t6040-cow-repro.sh"

python3 "$ROOT/scripts/reproducible-newc.py" "$TMP" | gzip -n -9 >"$DEST"
echo "initramfs -> $DEST"
shasum -a 256 "$DEST"
