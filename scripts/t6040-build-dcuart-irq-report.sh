#!/usr/bin/env bash
# Build only the TX-only IRQ-report initramfs. It reuses the already-built,
# storm-bounded BIT(1) kernel and DTB; this script performs no target access.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}

INIT_SOURCE="$ROOT/scripts/t6040-init-dcuart-irq-report" \
	DEST="$OUT/initramfs-dcuart-irq-report.cpio.gz" \
	bash "$ROOT/scripts/t6040-make-initramfs.sh"

shasum -a 256 \
	"$OUT/Image-dcuart-irq" \
	"$OUT/t6040-j614s-dcuart-irq.dtb" \
	"$OUT/initramfs-dcuart-irq-report.cpio.gz" \
	"$OUT/m1n1-t6040-logbuf-upper-guard-dryrun.bin"
