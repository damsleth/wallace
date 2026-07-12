#!/usr/bin/env bash
# Build (but do not boot) the gated J614s ANS/NVMe first-probe DTB.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
BUILD_DIR=${BUILD_DIR:-/build/linux-keyboard}
SOURCE=${SOURCE:-$ROOT/dts/t6040-j614s-dcuart-nvme.dts}
DEST=${DEST:-$OUT/t6040-j614s-dcuart-nvme.dtb}

cp "$SOURCE" "$OUT/t6040-j614s-dcuart-nvme.dts"
podman exec -e BUILD_DIR="$BUILD_DIR" kbuild bash -c '
    set -eu
    apple="$BUILD_DIR/arch/arm64/boot/dts/apple"
    cp /out/t6040-j614s-dcuart-nvme.dts "$apple/"
    cd "$BUILD_DIR"
    make ARCH=arm64 apple/t6040-j614s-dcuart-nvme.dtb
    cp "$apple/t6040-j614s-dcuart-nvme.dtb" /out/
'

echo "NVMe candidate (NOT APPROVED FOR BOOT) -> $DEST"
shasum -a 256 "$DEST"
