#!/usr/bin/env bash
# Build a host harness around m1n1's minilzlib, to reproduce exactly what
# XzDecode() does to a payload WITHOUT any rig time (ticket 160). It mirrors
# payload.c decompress_xz: dest_len starts at 1 GiB, XzDecode into a real buffer.
#
# The harness reproduces the target's pass/fail exactly (verified 2026-07-27:
# every object that boots decodes here, and the 278 MiB fat image that fails on
# the machine also returns "XZ decode failed" here). So a boot-blocking initramfs
# can be caught on the host before it ever costs a reboot.
#
# Usage:
#   bash scripts/t6040-minilzlib-harness.sh build
#   <builddir>/lzharness <file.xz>        # exit 0 = decodes, 1 = XZ decode failed
set -euo pipefail
M1N1=${M1N1:-/Users/damsleth/Code/m1n1}
SRC="$M1N1/src/minilzlib"
OUT=${OUT:-/private/tmp/t6040-lzharness}
[ -d "$SRC" ] || { echo "no minilzlib at $SRC (set M1N1=)" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT/minilzlib"
cp "$SRC"/*.c "$SRC"/*.h "$OUT/minilzlib/"
# stub utils.h resolves xzstream.c's #include "../utils.h" (it only wants printf)
printf '#ifndef UTILS_SHIM_H\n#define UTILS_SHIM_H\n#include <stdio.h>\n#endif\n' > "$OUT/utils.h"
cp "$(dirname "$0")/t6040-minilzlib-harness.c" "$OUT/harness.c"
cc -O2 -Wall -o "$OUT/lzharness" "$OUT/harness.c" "$OUT"/minilzlib/*.c 2>&1 | grep -v "multi-character" || true
echo "built $OUT/lzharness"
