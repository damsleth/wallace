#!/usr/bin/env bash
# Chainload exactly one self-contained raw m1n1 object over the KIS pty.
#
# This deliberately does not run linux.py or upload a second payload. The
# object's embedded m1n1 must discover and boot its own kernel/DTB/initramfs.
set -euo pipefail

source "$(dirname "$0")/rig-guard.sh"

M1=${M1N1DEVICE:-/tmp/m1n1}
M1N1_DIR=${M1N1_DIR:-/Users/damsleth/Code/m1n1}
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
OBJECT=${OBJECT:-$OUT/m1n1-b0-alpine-hid-restored.bin}
OBJECT_SHA=${OBJECT_SHA:-b50f52ab1fac473db2e9257c5363ef7905e4d1da5c8535fbf417209b09319172}
CONLOG=${CONLOG:-$OUT/raw-object-console.log}
CHAINLOAD_LOG=${CHAINLOAD_LOG:-$OUT/raw-object-chainload.log}
# m1n1 proxyclient needs the venv (construct, etc.); match t6040-boot-dcuart.sh.
PY=${PYTHON:-/Users/damsleth/Code/m1n1/venv/bin/python}

[ -e "$M1" ] || {
    echo "missing KIS pty: $M1" >&2
    exit 1
}
[ -f "$OBJECT" ] || {
    echo "missing raw object: $OBJECT" >&2
    exit 1
}

actual_sha=$(shasum -a 256 "$OBJECT" | awk '{print $1}')
[ "$actual_sha" = "$OBJECT_SHA" ] || {
    echo "raw-object SHA mismatch: $actual_sha != $OBJECT_SHA" >&2
    exit 1
}

stty -f "$M1" raw -echo
pkill -f "^cat $M1$" 2>/dev/null || true

echo "== one-object chainload: $OBJECT =="
echo "== sha256: $OBJECT_SHA =="
if ! (
    cd "$M1N1_DIR"
    M1N1DEVICE="$M1" timeout 300 "$PY" proxyclient/tools/chainload.py \
        -r "$OBJECT"
) >"$CHAINLOAD_LOG" 2>&1; then
    echo "chainload failed; last output:" >&2
    tail -20 "$CHAINLOAD_LOG" >&2
    stty -f "$M1" raw -echo 2>/dev/null || true
    nohup cat "$M1" >>"$CONLOG" 2>/dev/null < /dev/null &
    echo "console reader pid $! -> $CONLOG"
    exit 1
fi

: >"$CONLOG"
stty -f "$M1" raw -echo 2>/dev/null || true
nohup cat "$M1" >>"$CONLOG" 2>/dev/null < /dev/null &
reader_pid=$!
echo "single upload complete; console reader pid $reader_pid -> $CONLOG"
echo "No linux.py or second payload was invoked."
echo "Observe ttydc0 TX for the automatic Alpine report; send no target input."

if [ "${T6040_KEEPALIVE:-0}" = "1" ]; then
    wait "$reader_pid"
fi
