#!/usr/bin/env bash
# Build the separately gated J614s PCIe/WLAN/BT/SD bring-up image.
set -euo pipefail

ROOT=/Users/damsleth/Code/wallace
OUT=/Users/damsleth/Code/linux-build-out
# Use a dedicated tree so the long-running NVMe diagnostic tree's intentionally
# stacked instrumentation never leaks into (or blocks cleanup for) this image.
BUILD_DIR=${BUILD_DIR:-/build/linux-pcie}

cp "$ROOT/scripts/t6040-kbuild.sh" "$ROOT/patches/"*.patch "$OUT/"
cp "$ROOT/dts/t6040-j614s-dcuart-pcie.dts" "$OUT/"

podman exec \
    -e DOCKCHANNEL=1 \
    -e PCIE=1 \
    -e BUILD_DIR="$BUILD_DIR" \
    kbuild bash /out/t6040-kbuild.sh image

# The first attempt intentionally carries no PCIe endpoint modules. Reuse the
# proven DockChannel BusyBox userspace under a distinct artifact name.
cp "$OUT/initramfs-dcuart.cpio.gz" "$OUT/initramfs-dcuart-pcie.cpio.gz"

sha256sum \
    "$OUT/Image-pcie" \
    "$OUT/t6040-j614s-dcuart-pcie.dtb" \
    "$OUT/initramfs-dcuart-pcie.cpio.gz" \
    "$OUT/System.map-pcie"
