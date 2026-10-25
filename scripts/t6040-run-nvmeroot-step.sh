#!/usr/bin/env bash
# Ticket 5008: boot one 5005 payload (A sdroot-ro, B install, C nvmeroot) with
# hash checks. Step B enforces a host deadline: with no NVME-INSTALL PASS or
# STOP within DEADLINE seconds of handoff, the M4 is rebooted via DebugUSB.
# Then the installer checker runs. A and C only boot and capture the console.
#   usage: t6040-run-nvmeroot-step.sh A|B|C <run-dir>
# Requires the rig lease (boot-dcuart enforces it) and a running kisd.
set -u
STEP=${1:?A|B|C}; RUN=${2:?run directory}
case "$STEP" in
    A) P=nvmeroot-20261025/payload-A-sdroot-ro ;;
    B) P=nvmeroot-20261025/payload-B-install ;;
    C) P=nvmeroot-20261025/payload-C-nvmeroot ;;
    *) echo "step must be A, B or C" >&2; exit 2 ;;
esac
WALLACE=$(cd "$(dirname "$0")/.." && pwd)
O=/Users/damsleth/Code/linux-build-out
DEADLINE=${DEADLINE:-900}
[ ! -e "$RUN" ] || { echo "refusing to reuse $RUN" >&2; exit 2; }
mkdir -p "$RUN"
(cd "$O" && shasum -a 256 -c "$P/SHA256SUMS") >"$RUN/payload-check.txt" 2>&1 ||
    { echo "payload hash check failed" >&2; exit 1; }
cd "$WALLACE"
env -u EXTRA_BOOTARGS RIG_AGENT=claude RIG_ENFORCE=1 M1N1DEVICE=/tmp/m1n1 \
    M1N1_BIN=$O/$P/m1n1.bin IMAGE=$P/Image BOOT_MAXCPUS=1 BOOT_IDLE=nop \
    KERNEL_LOG_ARGS='ignore_loglevel printk.devkmsg=on console=ttydc0 console=tty0' \
    LOG_DIR="$RUN" CHAINLOAD_ATTEMPTS=1 BOOT_WAIT=5 T6040_KEEPALIVE=0 \
    bash scripts/t6040-boot-dcuart.sh $P/t6040-nvmeroot.dtb $P/initramfs.cpio.gz \
    >"$RUN/boot-script.out" 2>&1
echo "boot exit=$?" >>"$RUN/boot-script.out"
CON="$RUN/dcuart-console.log"
grep -q 'handoff done' "$RUN/boot-script.out" || { echo "no handoff; see $RUN/boot-script.out"; exit 1; }
[ "$STEP" = B ] || { echo "step $STEP handed off; console: $CON"; exit 0; }
t=0
while [ "$t" -lt "$DEADLINE" ]; do
    grep -qE 'NVME-INSTALL (PASS|STOP)|Kernel panic|SError' "$CON" 2>/dev/null && break
    sleep 5; t=$((t + 5))
done
# PASS is followed by a clean reboot -f; let its shutdown lines land.
sleep 30
if grep -q 'NVME-INSTALL PASS' "$CON"; then
    echo "result: PASS after ~${t}s"
elif grep -q 'NVME-INSTALL STOP' "$CON"; then
    echo "result: STOP after ~${t}s: $(grep -m1 -o 'NVME-INSTALL STOP.*' "$CON")"
else
    echo "result: DEADLINE ${DEADLINE}s exceeded or crash; rebooting via DebugUSB"
    sudo -n /usr/local/bin/macvdmtool reboot debugusb >"$RUN/deadline-reboot.txt" 2>&1
fi
echo "checker:"
python3 "$WALLACE/scripts/t6040-check-nvme-root-install-transcript.py" "$CON"
