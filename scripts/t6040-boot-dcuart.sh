#!/usr/bin/env bash
# Boot the t6040 kernel ENTIRELY over the DebugUSB (KIS) pty — no plain-cable
# tether, no screen-reading. Requires an attached kisd session (run
# ~/Code/wallace/scripts/t6040-debugusb-console.sh first; /tmp/m1n1 -> kisd pty).
#
# Flow:
#   1. chainload fresh m1n1 over the pty (proxy protocol)
#   2. linux.py uploads Image+DTB+initramfs and hands off
#   3. immediately attach a raw reader to the SAME pty: after handoff the
#      kernel's apple_dockchannel_tty owns the AP FIFO, so the pty carries
#      the Linux banner + a busybox shell (t6040-init-dcuart spawns it).
#
# After this script prints the banner, interact with:
#   printf 'uname -a\n' > /tmp/m1n1          # type into the shell
#   tail -f "$OUT/dcuart-console.log"        # watch output
# or attach interactively: screen /tmp/m1n1
#
# On a hung kernel the m1n1 watchdog warm-resets in ~20s; DebugUSB mode may
# need re-entering: sudo -n /usr/local/bin/macvdmtool debugusb
set -euo pipefail
M1=${M1N1DEVICE:-/tmp/m1n1}
OUT=/Users/damsleth/Code/linux-build-out
cd /Users/damsleth/Code/m1n1

PY=/Users/damsleth/Code/m1n1/venv/bin/python
[ -x "$PY" ] || PY=python3

DTB="${1:-t6040-j614s-dcuart.dtb}"
INITRAMFS="${2:-initramfs-dcuart.cpio.gz}"
IMAGE="${IMAGE:-Image}"
echo "== DTB: $DTB  kernel: $IMAGE  initramfs: $INITRAMFS  dev: $M1 =="

attach_reader() {
    stty -f "$M1" raw -echo 2>/dev/null || true
    # Detach from short-lived automation PTYs; otherwise their teardown can
    # reap the reader even though this function reports it as persistent.
    nohup cat "$M1" >> "$CONLOG" 2>/dev/null < /dev/null &
    CATPID=$!
    echo "console reader pid $CATPID -> $CONLOG"
}

# A reader is normally attached to keep the KIS stream draining, but it would
# steal proxy replies during chainload/linux.py. Own that transition here so a
# caller cannot accidentally leave the old reader racing the protocol.
pkill -f "^cat $M1$" 2>/dev/null || true

KERNEL_LOG_ARGS="${KERNEL_LOG_ARGS:-ignore_loglevel}"
CMDLINE="maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 $KERNEL_LOG_ARGS${EXTRA_BOOTARGS:+ $EXTRA_BOOTARGS} rdinit=/init"

echo "== chainload fresh m1n1 over $M1 =="
CHAINLOAD_LOG="$OUT/dcuart-chainload.log"
chainloaded=0
for attempt in 1 2; do
    if M1N1DEVICE=$M1 timeout 180 "$PY" proxyclient/tools/chainload.py \
        -r build/m1n1.bin > "$CHAINLOAD_LOG" 2>&1; then
        chainloaded=1
        grep -iE "Running proxy|TTY|Signature" "$CHAINLOAD_LOG" | head || true
        break
    fi
    echo "chainload attempt $attempt failed"
    tail -12 "$CHAINLOAD_LOG"
done
if [ "$chainloaded" -ne 1 ]; then
    CONLOG="$OUT/dcuart-console.log"
    attach_reader
    exit 1
fi

echo "== upload kernel + hand off =="
BOOTLOG="$OUT/dcuart-boot.log"
M1N1DEVICE=$M1 timeout 300 "$PY" proxyclient/tools/linux.py \
    "$OUT/$IMAGE" "$OUT/$DTB" "$OUT/$INITRAMFS" --compression none \
    --no-tty -b "$CMDLINE" 2>&1 | tee "$BOOTLOG" | tail -8 || true

if ! grep -q "Ready to boot" "$BOOTLOG"; then
    echo "ERROR: linux.py failed before the kernel handoff"
    CONLOG="$OUT/dcuart-console.log"
    attach_reader
    exit 1
fi

echo "== handoff done; attaching raw console reader to $M1 =="
CONLOG="$OUT/dcuart-console.log"
: > "$CONLOG"
attach_reader
echo "== first ${BOOT_WAIT:-30}s of Linux dockchannel output =="
sleep "${BOOT_WAIT:-30}"
tail -40 "$CONLOG"
echo
echo "== reader still running. Interact: printf 'cmd\\n' > $M1 ; tail -f $CONLOG =="
