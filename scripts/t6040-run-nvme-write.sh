#!/usr/bin/env bash
# Run one ticket-211/5003 exFAT write-test boot with an ENFORCED host deadline.
# The in-image watchdog keeps petting while a hung dd blocks, so only the host
# can stop a stuck run: if neither PASS nor STOP appears in the console log
# within DEADLINE seconds of handoff, the M4 is rebooted via DebugUSB.
#   usage: [PAYLOAD=dir] [WRITE_ARGS="nvmewritedir=TAG nvmewc=through"] \
#          t6040-run-nvme-write.sh write|verify <run-dir>
# Requires the rig lease (boot-dcuart enforces it) and a running kisd.
set -u
MODE=${1:?write|verify}; RUN=${2:?run directory}
case "$MODE" in write|verify) ;; *) echo "bad mode" >&2; exit 2 ;; esac
WALLACE=$(cd "$(dirname "$0")/.." && pwd)
O=/Users/damsleth/code/linux-build-out
P=${PAYLOAD:-nvme-exfat-write-20261025/payload}
DEADLINE=${DEADLINE:-300}
[ ! -e "$RUN" ] || { echo "refusing to reuse $RUN" >&2; exit 2; }
mkdir -p "$RUN"
(cd "$O" && shasum -a 256 -c "$P/SHA256SUMS") >"$RUN/payload-check.txt" 2>&1 ||
    { echo "payload hash check failed" >&2; exit 1; }
cd "$WALLACE"
env -u EXTRA_BOOTARGS RIG_AGENT=claude RIG_ENFORCE=1 M1N1DEVICE=/tmp/m1n1 \
    M1N1_BIN=$O/$P/m1n1.bin IMAGE=$P/Image BOOT_MAXCPUS=1 BOOT_IDLE=nop \
    KERNEL_LOG_ARGS='ignore_loglevel printk.devkmsg=on console=ttydc0 console=tty0' \
    EXTRA_BOOTARGS="nvmewrite=$MODE${WRITE_ARGS:+ $WRITE_ARGS}" LOG_DIR="$RUN" CHAINLOAD_ATTEMPTS=1 BOOT_WAIT=5 \
    T6040_KEEPALIVE=0 bash scripts/t6040-boot-dcuart.sh $P/t6040-nvme.dtb $P/initramfs.cpio.gz \
    >"$RUN/boot-script.out" 2>&1
echo "boot exit=$?" >>"$RUN/boot-script.out"
CON="$RUN/dcuart-console.log"
grep -q 'handoff done' "$RUN/boot-script.out" || { echo "no handoff; see $RUN/boot-script.out"; exit 1; }
t=0
while [ "$t" -lt "$DEADLINE" ]; do
    if grep -qE 'NVME-WRITE (PASS|STOP)|NVME-WRITE PARKED|Kernel panic|SError' "$CON" 2>/dev/null; then
        break
    fi
    sleep 5; t=$((t + 5))
done
sleep 10   # let the tail of the log land
if grep -q 'NVME-WRITE PASS' "$CON"; then
    echo "result: PASS after ~${t}s"
elif grep -q 'NVME-WRITE STOP' "$CON"; then
    echo "result: STOP after ~${t}s: $(grep -m1 -o 'NVME-WRITE STOP.*' "$CON")"
else
    echo "result: DEADLINE ${DEADLINE}s exceeded or crash; rebooting via DebugUSB"
    sudo -n /usr/local/bin/macvdmtool reboot debugusb >"$RUN/deadline-reboot.txt" 2>&1
fi
echo "checker:"
python3 "$WALLACE/scripts/t6040-check-nvme-write-transcript.py" --mode "$MODE" \
    ${EXPECT_SHA256:+--expect-sha256 "$EXPECT_SHA256"} "$CON"
