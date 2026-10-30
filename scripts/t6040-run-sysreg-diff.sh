#!/usr/bin/env bash
# Ticket 5010 fixture: chainload the m1n1 that starts Linux secondaries (7de07c71)
# over the enrolled rollback, wait for its proxy, then run the sysreg diff.


set -u
RUN=${1:?run directory}
M1N1_BIN=${M1N1_BIN:-/Users/damsleth/code/linux-build-out/nvme-exfat-write-20261025/payload/m1n1.bin}
M1N1_SHA256=${M1N1_SHA256:-7de07c714ebe8b26a408ab0a4719d10d2d208eb120eaac7d3aea03f0e36daf2a}
WALLACE=$(cd "$(dirname "$0")/.." && pwd)
[ ! -e "$RUN" ] || { echo "refusing to reuse $RUN" >&2; exit 2; }
mkdir -p "$RUN"
echo "$M1N1_SHA256  $M1N1_BIN" |
    shasum -a 256 -c - || exit 1
"$WALLACE/scripts/rig-lease.sh" status | grep -q 'HELD by claude' || { echo "no lease" >&2; exit 1; }
cd /Users/damsleth/code/m1n1
M1N1DEVICE=/tmp/m1n1 timeout 180 venv/bin/python proxyclient/tools/chainload.py -r "$M1N1_BIN" \
    >"$RUN/chainload.log" 2>&1 || { echo "chainload failed; see $RUN/chainload.log"; exit 1; }
sleep 5
timeout 30 venv/bin/python "$WALLACE/scripts/t6040-proxy-alive.py" --device /tmp/m1n1 --timeout 5 \
    >"$RUN/proxy-alive.txt" 2>&1 || { echo "chainloaded m1n1 has no proxy"; exit 1; }
M1N1DEVICE=/tmp/m1n1 timeout 300 venv/bin/python -u "$WALLACE/scripts/t6040-cpu-sysreg-diff.py" --out "$RUN/sysregs.json" ${SYSREG_ARGS:-} \
    2>&1 | tee "$RUN/sysreg-diff.log"
