#!/bin/bash
# Establish the DebugUSB (KIS) two-way console/proxy link to the t6040 target.
#
# Usage: bash ~/Code/wallace/scripts/t6040-debugusb-console.sh [reboot]
#   (no arg)  target already running -> just enter debugusb + attach kisd
#   reboot    reboot the target and re-enter debugusb during boot
#             (captures the full boot log including iBoot markers)
#
# Result: stable symlink /tmp/m1n1 -> kisd's pty. Use for everything:
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

KISD=""
for c in /usr/local/bin/kisd ~/Code/kisd/target/release/kisd ~/Code/kisd/target/debug/kisd; do
    [ -x "$c" ] && KISD="$c" && break
done
[ -n "$KISD" ] || { echo "kisd not found"; exit 1; }

LOG="${TMPDIR:-/tmp}/kisd-console.log"

# one kisd, freshly started, so the log and pty are always current
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

if [ "$1" = "reboot" ]; then
    sudo -n /usr/local/bin/macvdmtool reboot debugusb
else
    sudo -n /usr/local/bin/macvdmtool debugusb
fi

sleep 3
if grep -q "Device opened" "$LOG"; then
    echo "DebugUSB attached."
else
    echo "WARNING: kisd has not attached yet; check $LOG"
fi

echo
echo "console/proxy: /tmp/m1n1 -> $PTY"
echo "  export M1N1DEVICE=/tmp/m1n1"
echo "  screen /tmp/m1n1          # interactive console"
