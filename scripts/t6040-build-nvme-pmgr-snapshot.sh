#!/usr/bin/env bash
# Build, but do not boot, the T6040 raw-PMGR snapshot diagnostic.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
BUILD_DIR=${BUILD_DIR:-/build/linux-keyboard}
APPLE=$BUILD_DIR/arch/arm64/boot/dts/apple
DTB=t6040-j614s-dcuart-nvme-pmgr-snapshot.dtb
INITRAMFS=initramfs-dcuart-nvme-pmgr-snapshot.cpio.gz

cp "$ROOT/scripts/t6040-kbuild.sh" "$ROOT"/patches/*.patch "$OUT/"
podman exec \
    -e DOCKCHANNEL=1 \
    -e PMGR_FUNCTIONAL=1 \
    -e NVME=1 \
    -e NVME_MODE=staged \
    -e SART_TRACE=1 \
    -e NVME_PMGR_SNAPSHOT=1 \
    -e BUILD_DIR="$BUILD_DIR" \
    kbuild bash /out/t6040-kbuild.sh image

for src in \
    t6040-j614s-dcuart-nvme.dts \
    t6040-j614s-dcuart-nvme-ans-hold.dts \
    t6040-j614s-dcuart-nvme-pmgr-snapshot.dts; do
    cp "$ROOT/dts/$src" "$OUT/$src"
done

podman exec -e BUILD_DIR="$BUILD_DIR" -e DTB="$DTB" kbuild bash -c '
    set -eu
    apple="$BUILD_DIR/arch/arm64/boot/dts/apple"
    for src in \
        t6040-j614s-dcuart-nvme.dts \
        t6040-j614s-dcuart-nvme-ans-hold.dts \
        t6040-j614s-dcuart-nvme-pmgr-snapshot.dts; do
        cp "/out/$src" "$apple/$src"
    done
    cd "$BUILD_DIR"
    make ARCH=arm64 "apple/$DTB"
    cp "$apple/$DTB" /out/
'

INIT_SOURCE="$ROOT/scripts/t6040-init-dcuart" \
EXTRA_FILES="$OUT/nvme-core-pmgr-snapshot.ko:lib/modules/nvme-core.ko $OUT/nvme-apple-pmgr-snapshot.ko:lib/modules/nvme-apple.ko" \
DEST="$OUT/$INITRAMFS" \
    "$ROOT/scripts/t6040-make-initramfs.sh"

shasum -a 256 \
    "$OUT/Image-nvme-pmgr-snapshot" \
    "$OUT/$DTB" \
    "$OUT/$INITRAMFS" \
    "$OUT/nvme-core-pmgr-snapshot.ko" \
    "$OUT/nvme-apple-pmgr-snapshot.ko"
