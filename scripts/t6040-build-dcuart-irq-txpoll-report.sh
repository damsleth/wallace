#!/usr/bin/env bash
# Build the RX-IRQ/TX-poll reporter initramfs and print the complete live-test
# artifact manifest. This script performs no target access.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}

INIT_SOURCE="$ROOT/scripts/t6040-init-dcuart-irq-txpoll-report" \
	DEST="$OUT/initramfs-dcuart-irq-txpoll-report.cpio.gz" \
	bash "$ROOT/scripts/t6040-make-initramfs.sh"

shasum -a 256 \
	"$OUT/Image-dcuart-irq-txpoll" \
	"$OUT/t6040-j614s-dcuart-irq-txpoll.dtb" \
	"$OUT/initramfs-dcuart-irq-txpoll-report.cpio.gz" \
	"$OUT/m1n1-t6040-logbuf-upper-guard-dryrun.bin"
