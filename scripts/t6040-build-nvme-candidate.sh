#!/usr/bin/env bash
# Build (but do not boot) a gated J614s ANS/NVMe probe.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
BUILD_DIR=${BUILD_DIR:-/build/linux-keyboard}
SOURCE=${SOURCE:-$ROOT/dts/t6040-j614s-dcuart-nvme.dts}
PROBE_MODE=${PROBE_MODE:-builtin}
DT_SOURCE=$(basename "$SOURCE")
DT_TARGET=${DT_SOURCE%.dts}.dtb
DEST=${DEST:-$OUT/$DT_TARGET}

case "$PROBE_MODE" in
    builtin|staged) ;;
    *)
        echo "ERROR: unknown PROBE_MODE=$PROBE_MODE; use builtin or staged" >&2
        exit 1
        ;;
esac

# Build a separate kernel with either the original built-in probe or a staged
# apple-nvme module. The default Image is not overwritten.
cp "$ROOT/scripts/t6040-kbuild.sh" "$ROOT"/patches/*.patch "$OUT/"
podman exec -e DOCKCHANNEL=1 -e PMGR_FUNCTIONAL=1 -e NVME=1 \
    -e NVME_MODE="$PROBE_MODE" \
    -e BUILD_DIR="$BUILD_DIR" kbuild bash /out/t6040-kbuild.sh image

cp "$SOURCE" "$OUT/$DT_SOURCE"
podman exec -e BUILD_DIR="$BUILD_DIR" -e DT_SOURCE="$DT_SOURCE" \
    -e DT_TARGET="$DT_TARGET" kbuild bash -c '
    set -eu
    apple="$BUILD_DIR/arch/arm64/boot/dts/apple"
    cp "/out/$DT_SOURCE" "$apple/"
    cd "$BUILD_DIR"
    make ARCH=arm64 "apple/$DT_TARGET"
    cp "$apple/$DT_TARGET" /out/
'
if [ "$DEST" != "$OUT/$DT_TARGET" ]; then
    cp "$OUT/$DT_TARGET" "$DEST"
fi

echo "NVMe $PROBE_MODE candidate (NOT APPROVED FOR BOOT) -> $DEST"
if [ "$PROBE_MODE" = staged ]; then
    EXTRA_FILES="$OUT/nvme-core.ko:lib/modules/nvme-core.ko $OUT/nvme-apple.ko:lib/modules/nvme-apple.ko" \
        DEST="$OUT/initramfs-dcuart-nvme-staged.cpio.gz" \
        "$ROOT/scripts/t6040-make-initramfs.sh"
    shasum -a 256 "$OUT/Image-nvme-staged" "$OUT/nvme-core.ko" \
        "$OUT/nvme-apple.ko" "$OUT/initramfs-dcuart-nvme-staged.cpio.gz"
else
    shasum -a 256 "$OUT/Image-nvme"
fi
shasum -a 256 "$DEST"
