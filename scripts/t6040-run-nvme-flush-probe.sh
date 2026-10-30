#!/usr/bin/env bash
# Ticket 5006 fixture: chainload the NVMe-fixed m1n1 7de07c71 (as 5001/6001)
# over the enrolled rollback, wait for its proxy, then run the flush probe.
# The rollback m1n1 predates the July-30 NVMe fixes; nvme_init on it is the
# path that raised the July-25 SError, so it is never used directly.
set -u
RUN=${1:?run directory}
M1N1_BIN=/Users/damsleth/code/linux-build-out/nvme-exfat-write-20261025/payload/m1n1.bin
WALLACE=$(cd "$(dirname "$0")/.." && pwd)
[ ! -e "$RUN" ] || { echo "refusing to reuse $RUN" >&2; exit 2; }
mkdir -p "$RUN"
echo "7de07c714ebe8b26a408ab0a4719d10d2d208eb120eaac7d3aea03f0e36daf2a  $M1N1_BIN" |
    shasum -a 256 -c - || exit 1
"$WALLACE/scripts/rig-lease.sh" status | grep -q 'HELD by claude' || { echo "no lease" >&2; exit 1; }
cd /Users/damsleth/code/m1n1
M1N1DEVICE=/tmp/m1n1 timeout 180 venv/bin/python proxyclient/tools/chainload.py -r "$M1N1_BIN" \
    >"$RUN/chainload.log" 2>&1 || { echo "chainload failed; see $RUN/chainload.log"; exit 1; }
sleep 5
timeout 30 venv/bin/python "$WALLACE/scripts/t6040-proxy-alive.py" --device /tmp/m1n1 --timeout 5 \
    >"$RUN/proxy-alive.txt" 2>&1 || { echo "chainloaded m1n1 has no proxy"; exit 1; }
M1N1DEVICE=/tmp/m1n1 timeout 120 venv/bin/python "$WALLACE/scripts/t6040-nvme-flush-probe.py" \
    2>&1 | tee "$RUN/flush-probe.log"
