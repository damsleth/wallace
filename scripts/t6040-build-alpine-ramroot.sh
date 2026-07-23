#!/usr/bin/env bash
# Build a reproducible Alpine aarch64 root-as-initramfs for T6040/J614s.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
ALPINE_VERSION=${ALPINE_VERSION:-3.24.0}
ALPINE_ARCH=${ALPINE_ARCH:-aarch64}
ALPINE_SHA256=${ALPINE_SHA256:-4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a}
ALPINE_FILE="alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
ALPINE_URL=${ALPINE_URL:-"https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/${ALPINE_ARCH}/${ALPINE_FILE}"}
ARCHIVE="$OUT/$ALPINE_FILE"
DEST=${DEST:-"$OUT/initramfs-alpine-ramroot.cpio.gz"}
CONTAINER=${CONTAINER:-kbuild}

case "$DEST" in
    "$OUT"/*) ;;
    *) echo "DEST must be directly under $OUT" >&2; exit 1 ;;
esac

mkdir -p "$OUT"
if [ ! -f "$ARCHIVE" ]; then
    curl -fL --retry 3 --output "$ARCHIVE.part" "$ALPINE_URL"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
printf '%s  %s\n' "$ALPINE_SHA256" "$ARCHIVE" | shasum -a 256 -c -

TMP=$(mktemp -d "$OUT/alpine-ramroot.XXXXXX")
TMP_BASE=$(basename "$TMP")
DEST_BASE=$(basename "$DEST")
DEST_TMP=$(mktemp "$OUT/.${DEST_BASE}.XXXXXX")
DEST_TMP_BASE=$(basename "$DEST_TMP")
case "$DEST_BASE" in
    *.cpio.gz) LIST="$OUT/${DEST_BASE%.cpio.gz}.contents" ;;
    *) LIST="$OUT/$DEST_BASE.contents" ;;
esac
trap '
    podman exec "$CONTAINER" rm -rf "/out/$TMP_BASE" >/dev/null 2>&1 || true
    rm -f "$DEST_TMP"
' EXIT

LC_ALL=C bsdtar -xf "$ARCHIVE" -C "$TMP"
install -d \
    "$TMP/dev" \
    "$TMP/proc" \
    "$TMP/sys" \
    "$TMP/run" \
    "$TMP/tmp" \
    "$TMP/root" \
    "$TMP/usr/local/sbin"
install -m 0755 "$ROOT/scripts/t6040-init-alpine-ramroot" "$TMP/init"
install -m 0755 \
    "$ROOT/scripts/t6040-hid-trace-auto-report" \
    "$TMP/usr/local/sbin/t6040-hid-trace-auto-report"

if find "$TMP" -type b -print -quit | grep -q .; then
    echo "RAM-root source unexpectedly contains a block-device node" >&2
    exit 1
fi

# Normalize timestamps before GNU cpio supplies deterministic inode numbers and
# root ownership. gzip -n removes its own timestamp and source-name fields.
find "$TMP" -exec touch -h -t 202001010000 {} +
podman exec \
    -e RAMROOT_DIR="/out/$TMP_BASE" \
    -e RAMROOT_DEST="/out/$DEST_TMP_BASE" \
    "$CONTAINER" bash -c '
        set -euo pipefail
        cd "$RAMROOT_DIR"
        find . -print0 |
            LC_ALL=C sort -z |
            cpio --null -o --format=newc --owner=0:0 --reproducible 2>/dev/null |
            gzip -n -9 >"$RAMROOT_DEST"
    '
gzip -t "$DEST_TMP"
chmod 0644 "$DEST_TMP"
mv "$DEST_TMP" "$DEST"

LC_ALL=C gzip -dc "$DEST" | LC_ALL=C cpio -it 2>/dev/null | LC_ALL=C sort >"$LIST"

for required in \
    init \
    bin/busybox \
    etc/alpine-release \
    lib/ld-musl-aarch64.so.1 \
    usr/local/sbin/t6040-hid-trace-auto-report
do
    grep -qx "$required" "$LIST" || {
        echo "missing required RAM-root entry: $required" >&2
        exit 1
    }
done

echo "Alpine source: $ALPINE_URL"
shasum -a 256 "$ARCHIVE" "$DEST" "$LIST"
ls -lh "$ARCHIVE" "$DEST"
