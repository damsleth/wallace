#!/bin/bash
# Establish the DebugUSB (KIS) two-way console/proxy link to the t6040 target.
#
# Usage: bash ~/Code/wallace/scripts/t6040-debugusb-console.sh [reboot]
#   (no arg)  target already running -> just enter debugusb + attach kisd
#   reboot    reboot the target and re-enter debugusb during boot
#             (captures the full boot log including iBoot markers)
#
# Result: stable symlink /tmp/m1n1 -> kisd's pty, with a background reader
# draining console output to /tmp/m1n1-console.log. Use for everything:
#   export M1N1DEVICE=/tmp/m1n1     # proxyclient tools
#   screen /tmp/m1n1                # interactive console
#
# Requires:
#  - /usr/local/bin/macvdmtool (root-owned, NOPASSWD sudoers entry)
#  - /usr/local/bin/kisd (or a cargo build in ~/Code/kisd)
#  - DP/TB cable in the M4's DFU port
#  - proxy.py local patch (raw pty termios + baud-ioctl tolerance)
#
# Notes:
#  - DebugUSB replaces m1n1's USB gadget on the DFU port (no /dev/cu.usbmodem*
#    while active). Use another port + plain cable for fast USB chainload.
#  - kisd auto-detects the t6040 KIS base (0x548700000, protocol 4.00).
#    Channel 0 is the AP dockchannel-uart. kisd's own /dev/m1n1 symlink is
#    impossible on macOS (devfs) - hence the /tmp/m1n1 symlink here.
#  - iBoot's output is hash-redacted (production fuses); m1n1's is plaintext.

set -e

# rig turn-taking: refuse if the OTHER agent holds a live lease. This is the
# recovery/link script, so it may run while NEEDS_RECOVERY is set (its job);
# after it re-establishes a healthy proxy, run: rig-lease.sh recovered <agent>.
: "${RIG_ALLOW_RECOVERY:=1}"
source "$(dirname "$0")/rig-guard.sh"

KISD=""
for c in /usr/local/bin/kisd ~/Code/kisd/target/release/kisd ~/Code/kisd/target/debug/kisd; do
    [ -x "$c" ] && KISD="$c" && break
done
[ -n "$KISD" ] || { echo "kisd not found"; exit 1; }

LOG="${TMPDIR:-/tmp}/kisd-console.log"
CONSOLE_LOG=/tmp/m1n1-console.log

# one kisd, freshly started, so the log and pty are always current
pkill -f '^cat /tmp/m1n1$' 2>/dev/null || true
pkill -x kisd 2>/dev/null && sleep 1
# Detach from short-lived automation shells as well as interactive terminals;
# otherwise their exit can reap kisd and leave /tmp/m1n1 dangling.
nohup env RUST_LOG=info "$KISD" > "$LOG" 2>&1 < /dev/null &
echo "started kisd (log: $LOG)"
sleep 2

PTY=$(grep -o "pty /dev/ttys[0-9]*" "$LOG" | head -1 | cut -d' ' -f2)
[ -n "$PTY" ] || { echo "kisd pty not found; check $LOG"; exit 1; }
ln -sf "$PTY" /tmp/m1n1

# kisd cannot put the PTY master into raw mode on macOS. Configure the slave
# before any console reader is attached: m1n1's binary startup reply begins
# ff 55 aa 04, and canonical mode consumes byte 04 as VEOF. A cat then appears
# to drain the text console but leaves the proxy protocol unusable.
stty -f /tmp/m1n1 raw -echo

: > "$CONSOLE_LOG"
nohup cat /tmp/m1n1 >> "$CONSOLE_LOG" 2>/dev/null < /dev/null &
READER_PID=$!
echo "console reader pid $READER_PID -> $CONSOLE_LOG"

if [ "$1" = "reboot" ]; then
    if ! sudo -n /usr/local/bin/macvdmtool reboot debugusb; then
        echo "ERROR: reboot/DebugUSB entry failed; reader remains attached"
        exit 1
    fi

    proxy_ready=0
    for ((i = 0; i < 25; i++)); do
        if grep -a -q 'Running proxy' "$CONSOLE_LOG"; then
            proxy_ready=1
            break
        fi
        sleep 1
    done
    if [ "$proxy_ready" -ne 1 ]; then
        echo "ERROR: m1n1 did not reach Running proxy within 25s; reader remains attached"
        exit 1
    fi

    # Do not hand the PTY to proxyclient while old DockChannel output is still
    # arriving. Three unchanged one-second samples bound the startup drain.
    stable=0
    last_size=-1
    for ((i = 0; i < 10; i++)); do
        size=$(wc -c < "$CONSOLE_LOG")
        if [ "$size" -eq "$last_size" ]; then
            stable=$((stable + 1))
            [ "$stable" -ge 3 ] && break
        else
            stable=0
            last_size=$size
        fi
        sleep 1
    done
    if [ "$stable" -lt 3 ]; then
        echo "ERROR: console did not become quiescent; reader remains attached"
        exit 1
    fi
    echo "m1n1 proxy ready; console quiescent at $last_size bytes"
else
    if ! sudo -n /usr/local/bin/macvdmtool debugusb; then
        echo "ERROR: DebugUSB entry failed; reader remains attached"
        exit 1
    fi
fi

sleep 3
if grep -q "Device opened" "$LOG"; then
    echo "DebugUSB attached."
else
    echo "WARNING: kisd has not attached yet; check $LOG"
fi

echo
echo "console/proxy: /tmp/m1n1 -> $PTY"
echo "  reader: pid $READER_PID -> $CONSOLE_LOG"
echo "  export M1N1DEVICE=/tmp/m1n1"
echo "  stop reader pid $READER_PID before a manual proxyclient or screen session"
echo "  screen /tmp/m1n1          # interactive console"

# Short-lived automation shells may reap their whole process group even after
# nohup. Agent-driven sessions set this so the script itself anchors kisd and
# the reader until the reader exits or the session is interrupted.
if [ "${T6040_KEEPALIVE:-0}" = "1" ]; then
    echo "keeping DebugUSB process group alive"
    wait "$READER_PID"
fi
