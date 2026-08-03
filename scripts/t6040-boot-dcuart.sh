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
# rig turn-taking: refuse if the OTHER agent holds a live lease; warn (proceed)
# on an idle rig. Set RIG_AGENT=<you>; hold the lease via scripts/rig-lease.sh.
source "$(dirname "$0")/rig-guard.sh"
M1=${M1N1DEVICE:-/tmp/m1n1}
OUT=/Users/damsleth/Code/linux-build-out
cd /Users/damsleth/Code/m1n1

PY=/Users/damsleth/Code/m1n1/venv/bin/python
[ -x "$PY" ] || PY=python3

DTB="${1:-t6040-j614s-dcuart.dtb}"
INITRAMFS="${2:-initramfs-dcuart.cpio.gz}"
IMAGE="${IMAGE:-Image}"
M1N1_BIN="${M1N1_BIN:-build/m1n1.bin}"
echo "== m1n1: $M1N1_BIN  DTB: $DTB  kernel: $IMAGE  initramfs: $INITRAMFS  dev: $M1 =="

# Refuse a kernel that is missing entire driver subsystems.
#
# $OUT/Image is what actually boots, and per-build "Image-<name>" artifacts do
# NOT update it -- so it can silently stay weeks old. On 2026-08-03 it was still
# the Jul 24 build, which contains zero occurrences of pcie-apple and macsmc.
# That cost an evening of false hardware diagnoses (empty /sys/bus/pci/devices,
# GL9755 "absent", no mmcblk0, no wlan0, no /dev/input so a dead keyboard, and a
# silent dockchannel console) and two needless physical interventions.
#
# A whole subsystem missing means the wrong kernel, not broken hardware. Set
# BOOT_SKIP_IMAGE_CHECK=1 when a deliberately minimal kernel is the point.
if [ "${BOOT_SKIP_IMAGE_CHECK:-0}" != 1 ]; then
    for _sym in pcie-apple macsmc; do
        if [ "$(strings -a "$OUT/$IMAGE" 2>/dev/null | grep -ci "$_sym")" -eq 0 ]; then
            echo "ERROR: $OUT/$IMAGE contains no '$_sym' -- it lacks whole driver subsystems."
            echo "       version: $(strings -a "$OUT/$IMAGE" 2>/dev/null | grep -m1 'Linux version' | cut -c1-72)"
            echo "       date:    $(command ls -l "$OUT/$IMAGE" | awk '{print $6, $7, $8}')"
            echo "       Fix: copy the intended Image-<name> over $OUT/$IMAGE, or rebuild."
            echo "       Override with BOOT_SKIP_IMAGE_CHECK=1 if a minimal kernel is intended."
            exit 1
        fi
    done
    echo "== kernel check: pcie-apple + macsmc present ($(command ls -l "$OUT/$IMAGE" | awk '{print $6, $7, $8}')) =="
fi

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
# maxcpus and idle are overridable so experiments do not end up with two
# conflicting copies on the cmdline (which made the ticket-205 idle=yield test
# inconclusive on 2026-08-03 -- both idle=nop and idle=yield were present).
BOOT_MAXCPUS="${BOOT_MAXCPUS:-1}"
BOOT_IDLE="${BOOT_IDLE:-nop}"
CMDLINE="maxcpus=$BOOT_MAXCPUS idle=$BOOT_IDLE nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 $KERNEL_LOG_ARGS${EXTRA_BOOTARGS:+ $EXTRA_BOOTARGS} rdinit=/init"

echo "== chainload fresh m1n1 over $M1 =="
CHAINLOAD_LOG="$OUT/dcuart-chainload.log"
chainloaded=0
for attempt in 1 2; do
    if M1N1DEVICE=$M1 timeout 180 "$PY" proxyclient/tools/chainload.py \
        -r "$M1N1_BIN" > "$CHAINLOAD_LOG" 2>&1; then
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
if [ "${T6040_KEEPALIVE:-0}" = "1" ]; then
    echo "== keeping Linux console process group alive =="
    wait "$CATPID"
fi
