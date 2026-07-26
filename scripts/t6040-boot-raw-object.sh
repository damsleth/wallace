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
DEFAULT_OBJECT=$OUT/m1n1-b0-alpine-hid-restored.bin
DEFAULT_OBJECT_SHA=b50f52ab1fac473db2e9257c5363ef7905e4d1da5c8535fbf417209b09319172
CONLOG=${CONLOG:-$OUT/raw-object-console.log}
CHAINLOAD_LOG=${CHAINLOAD_LOG:-$OUT/raw-object-chainload.log}
# m1n1 proxyclient needs the venv (construct, etc.); match t6040-boot-dcuart.sh.
PY=${PYTHON:-/Users/damsleth/Code/m1n1/venv/bin/python}

usage() {
    cat >&2 <<USAGE
usage: $(basename "$0") [OBJECT_PATH]

Chainload exactly one self-contained raw m1n1 object over the KIS pty.

The object may be given as the first argument OR via OBJECT=; both are accepted
and unknown/extra arguments are a hard error. Whenever the object is not the
pinned default, OBJECT_SHA= must be given explicitly, so a run can only ever
boot the exact bytes that were reviewed.

  OBJECT=<path> OBJECT_SHA=<sha256> M1N1DEVICE=/tmp/m1n1 $(basename "$0")
  OBJECT_SHA=<sha256> M1N1DEVICE=/tmp/m1n1 $(basename "$0") <path>

default object: $DEFAULT_OBJECT
env: M1N1DEVICE OBJECT OBJECT_SHA OUT M1N1_DIR PYTHON CONLOG CHAINLOAD_LOG T6040_KEEPALIVE
USAGE
}

# Was OBJECT_SHA set by the caller (as opposed to defaulted below)?
sha_explicit=${OBJECT_SHA+yes}

if [ "$#" -gt 1 ]; then
    echo "unexpected extra arguments: $*" >&2
    usage
    exit 2
fi
arg=${1:-}
case "$arg" in
    -h|--help) usage; exit 0 ;;
    -*)        echo "unknown option: $arg" >&2; usage; exit 2 ;;
esac

# A positional path and OBJECT= must not disagree; silently preferring one of
# them is exactly how a run boots something other than what was intended.
if [ -n "$arg" ] && [ -n "${OBJECT:-}" ] && [ "$arg" != "${OBJECT:-}" ]; then
    echo "conflicting object: argument '$arg' != OBJECT '$OBJECT'" >&2
    echo "pass it one way only" >&2
    exit 2
fi
OBJECT=${arg:-${OBJECT:-$DEFAULT_OBJECT}}

[ -e "$M1" ] || {
    echo "missing KIS pty: $M1" >&2
    exit 1
}
[ -f "$OBJECT" ] || {
    echo "missing raw object: $OBJECT" >&2
    exit 1
}

actual_sha=$(shasum -a 256 "$OBJECT" | awk '{print $1}')

# Overriding the object without pinning its hash would otherwise fall through to
# the DEFAULT hash and report a confusing "mismatch" against a file you did not
# name. Fail with the hash you need instead.
if [ "$OBJECT" != "$DEFAULT_OBJECT" ] && [ -z "$sha_explicit" ]; then
    echo "refusing to boot a non-default object without an explicit OBJECT_SHA" >&2
    echo "  object: $OBJECT" >&2
    echo "  sha256: $actual_sha" >&2
    echo "re-run with OBJECT_SHA=$actual_sha" >&2
    exit 2
fi
OBJECT_SHA=${OBJECT_SHA:-$DEFAULT_OBJECT_SHA}

[ "$actual_sha" = "$OBJECT_SHA" ] || {
    echo "raw-object SHA mismatch for $OBJECT" >&2
    echo "  actual:   $actual_sha" >&2
    echo "  expected: $OBJECT_SHA" >&2
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
