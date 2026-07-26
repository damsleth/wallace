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
CONLOG=${CONLOG:-$OUT/raw-object-console.log}
CHAINLOAD_LOG=${CHAINLOAD_LOG:-$OUT/raw-object-chainload.log}
# m1n1 proxyclient needs the venv (construct, etc.); match t6040-boot-dcuart.sh.
PY=${PYTHON:-/Users/damsleth/Code/m1n1/venv/bin/python}

usage() {
    cat >&2 <<USAGE
usage: $(basename "$0") <OBJECT_PATH> <SHA256>

Chainload exactly one self-contained raw m1n1 object over the KIS pty.

There is deliberately NO default object. Both the object and its expected
sha256 must be named on every run, so this script can never boot bytes the
caller did not ask for. Prefer the positional form: it survives being pasted
with semicolons between the values, which env-var assignments do not.

  $(basename "$0") <path> <sha256>            # recommended
  OBJECT=<path> OBJECT_SHA=<sha256> $(basename "$0")   # env form (spaces only!)

env: M1N1DEVICE (default /tmp/m1n1) OBJECT OBJECT_SHA OUT M1N1_DIR PYTHON
     CONLOG CHAINLOAD_LOG T6040_KEEPALIVE
USAGE
}

if [ "$#" -gt 2 ]; then
    echo "unexpected extra arguments: $*" >&2
    usage
    exit 2
fi
arg_obj=${1:-}
arg_sha=${2:-}
case "$arg_obj" in
    -h|--help) usage; exit 0 ;;
    -*)        echo "unknown option: $arg_obj" >&2; usage; exit 2 ;;
esac

# A positional value and its env twin must not disagree; silently preferring one
# is exactly how a run boots something other than what was intended.
if [ -n "$arg_obj" ] && [ -n "${OBJECT:-}" ] && [ "$arg_obj" != "${OBJECT:-}" ]; then
    echo "conflicting object: argument '$arg_obj' != OBJECT '$OBJECT'" >&2
    echo "pass it one way only" >&2
    exit 2
fi
if [ -n "$arg_sha" ] && [ -n "${OBJECT_SHA:-}" ] && [ "$arg_sha" != "${OBJECT_SHA:-}" ]; then
    echo "conflicting sha: argument '$arg_sha' != OBJECT_SHA '$OBJECT_SHA'" >&2
    echo "pass it one way only" >&2
    exit 2
fi

OBJECT=${arg_obj:-${OBJECT:-}}
OBJECT_SHA=${arg_sha:-${OBJECT_SHA:-}}

# No default object, by design. Two rig cycles were burned booting a hardcoded
# default: once because a positional path was ignored, and once because
# `VAR=x; VAR=y; cmd` sets shell-local variables that never reach the child, so
# the script saw an empty environment and its default looked perfectly valid.
# A missing value must stop the run, not select something historical.
if [ -z "$OBJECT" ]; then
    echo "no object given: name the object explicitly (there is no default)" >&2
    usage
    exit 2
fi
if [ -z "$OBJECT_SHA" ]; then
    echo "no OBJECT_SHA given: the exact bytes must be pinned on every run" >&2
    if [ -f "$OBJECT" ]; then
        echo "  object: $OBJECT" >&2
        echo "  sha256: $(shasum -a 256 "$OBJECT" | awk '{print $1}')" >&2
    fi
    usage
    exit 2
fi

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
    echo "raw-object SHA mismatch for $OBJECT" >&2
    echo "  actual:   $actual_sha" >&2
    echo "  expected: $OBJECT_SHA" >&2
    exit 1
}

stty -f "$M1" raw -echo
pkill -f "^cat $M1$" 2>/dev/null || true

# Ticket 157: prove a LIVE proxy is behind the pty before uploading. `[ -e "$M1" ]` above
# only proves a symlink exists — on 2026-07-26 that passed three times against a dead pty
# (once a stale kisd, twice because a previous chainload had booted Linux and CONSUMED the
# proxy), each costing a silent 5-minute timeout with a 0-byte log. Skip with
# T6040_SKIP_PREFLIGHT=1.
if [ "${T6040_SKIP_PREFLIGHT:-0}" != "1" ]; then
    if ! "$PY" "$(dirname "$0")/t6040-proxy-alive.py" --device "$M1" --timeout 5; then
        echo "refusing to upload $(basename "$OBJECT") into a dead proxy" >&2
        stty -f "$M1" raw -echo 2>/dev/null || true
        nohup cat "$M1" >>"$CONLOG" 2>/dev/null < /dev/null &
        echo "console reader pid $! -> $CONLOG" >&2
        exit 1
    fi
fi

echo "== one-object chainload: $OBJECT =="
echo "== sha256: $OBJECT_SHA =="

# Ticket 158. Three defects in the old one-liner, all of which cost real rig time on
# 2026-07-26:
#
#  1. ORPHANS. `timeout` was reparented to init when this script's parent was killed, and
#     its python child kept running — one such orphan had pushed ~41 MiB into the pty and
#     then sat holding it, silently corrupting the maintainer's next two runs (the target
#     stayed at `Running proxy` because two writers interleaved on one transport). `set -m`
#     puts the job in its own process group so the EXIT trap can kill the WHOLE group.
#  2. NO PROGRESS. Python block-buffers stdout to a file, so the log stayed 0 bytes until
#     exit and a healthy upload was indistinguishable from a hang. PYTHONUNBUFFERED=1 makes
#     the log fill live, so `tail -f` shows the progress dots.
#  3. FIXED 300 s TIMEOUT. Measured rate over KIS is ~0.7 MB/s (83 MB took ~2 min), so 300 s
#     was already marginal for the fat object and hopeless for anything larger — and the
#     capability-first policy (ticket 155) makes objects bigger, not smaller. Scale it.
object_mib=$(( $(wc -c < "$OBJECT") / 1048576 ))
CHAINLOAD_TIMEOUT=${T6040_CHAINLOAD_TIMEOUT:-$(( 120 + object_mib * 5 ))}
echo "== ${object_mib} MiB, timeout ${CHAINLOAD_TIMEOUT}s; live progress: tail -f $CHAINLOAD_LOG =="

chainload_pgid=""
kill_chainload() {
    [ -n "$chainload_pgid" ] || return 0
    kill -TERM "-$chainload_pgid" 2>/dev/null || true
    sleep 1
    kill -KILL "-$chainload_pgid" 2>/dev/null || true
}
trap kill_chainload EXIT INT TERM

set +e
set -m   # own process group per job, so the trap can kill the group, not just the wrapper
(
    cd "$M1N1_DIR"
    exec env PYTHONUNBUFFERED=1 M1N1DEVICE="$M1" \
        timeout "$CHAINLOAD_TIMEOUT" "$PY" proxyclient/tools/chainload.py -r "$OBJECT"
) >"$CHAINLOAD_LOG" 2>&1 &
chainload_pgid=$!
set +m
wait "$chainload_pgid"
chainload_rc=$?
chainload_pgid=""   # completed normally; nothing left to kill
trap - EXIT INT TERM
set -e

# Judge the run from the LOG, never from chainload.py's exit status (ticket 151).
# chainload.py ends with `iface.nop(); print("Proxy is alive again")`. For a one-object
# smoke the payload boots Linux, Linux takes the UART, and that nop() therefore MUST time
# out — so a non-zero exit is the NORMAL outcome of a SUCCESSFUL boot. Reporting it as
# "chainload failed" made a passing ticket-147 run look failed and cost real time.
# Markers below are the ones actually observed in the 2026-07-26 logs.
m1n1_handoffs=$(grep -c "Vectoring to next stage" "$CHAINLOAD_LOG" || true)
verdict=""
rc=0
if grep -q "No valid payload found" "$CHAINLOAD_LOG"; then
    verdict="FAIL — m1n1 rejected the payload (\"No valid payload found\")"; rc=1
elif grep -qE "Kernel panic|Oops:|Unable to handle kernel" "$CHAINLOAD_LOG"; then
    verdict="FAIL — kernel fault during boot"; rc=1
elif grep -q "SHA mismatch\|Traceback" "$CHAINLOAD_LOG" && [ "$m1n1_handoffs" -eq 0 ]; then
    verdict="FAIL — chainload never reached handoff (rc=$chainload_rc)"; rc=1
elif grep -q "Valid payload found" "$CHAINLOAD_LOG" && [ "$m1n1_handoffs" -ge 2 ]; then
    verdict="OK — payload accepted and kernel entered (proxy loss after handoff is expected)"
elif grep -q "Proxy is alive again" "$CHAINLOAD_LOG"; then
    verdict="OK — chainloaded stage returned a live proxy (payload-free loader, no boot)"
elif [ "$m1n1_handoffs" -ge 1 ]; then
    verdict="INCONCLUSIVE — handed off but no payload-accepted marker; read the log"
else
    verdict="FAIL — no handoff marker in log (rc=$chainload_rc)"; rc=1
fi

: >"$CONLOG"
stty -f "$M1" raw -echo 2>/dev/null || true
nohup cat "$M1" >>"$CONLOG" 2>/dev/null < /dev/null &
reader_pid=$!

echo "== verdict: $verdict =="
echo "   chainload.py rc=$chainload_rc (not a verdict), handoffs=$m1n1_handoffs, log=$CHAINLOAD_LOG"
if grep -q "health report end" "$CHAINLOAD_LOG"; then
    echo "   userspace: B0 health report reached its END marker"
elif grep -qE ":~#|/ #|~ #" "$CHAINLOAD_LOG"; then
    echo "   userspace: a shell prompt appeared"
else
    echo "   userspace: nothing echoed to this pty — normal for a console=tty0-only image;"
    echo "             read the panel, or see ticket 153 (capture dmesg over KIS)"
fi
if [ "$rc" -ne 0 ]; then
    echo "   last output:" >&2
    tail -20 "$CHAINLOAD_LOG" >&2
fi
echo "console reader pid $reader_pid -> $CONLOG"
echo "No linux.py or second payload was invoked."

if [ "${T6040_KEEPALIVE:-0}" = "1" ]; then
    wait "$reader_pid"
fi

exit "$rc"
