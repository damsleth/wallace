#!/usr/bin/env bash
# Bring up the host half of the reviewed PPP-tether candidate.
#
# Native mode requires an explicitly named Linux gadget tty:
#   scripts/t6040-usb-ppp-host.sh /dev/cu.usbmodem...
#
# Fallback mode uses the exact-product-gated libusb bridge, so it cannot claim
# m1n1's own proxy gadget despite the shared VID/PID:
#   scripts/t6040-usb-ppp-host.sh --libusb
#
# This script never creates /etc/ppp/options. Apple's pppd requires that file
# to exist even with all options on the command line; creating the empty file
# is a one-time, explicit host-admin action for CJ.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PPPD=/usr/sbin/pppd
BRIDGE_PID=
TMP=

cleanup()
{
    [ -z "$BRIDGE_PID" ] || kill "$BRIDGE_PID" 2>/dev/null || true
    [ -z "$BRIDGE_PID" ] || wait "$BRIDGE_PID" 2>/dev/null || true
    [ -z "$TMP" ] || rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

[ -x "$PPPD" ] || { echo "missing $PPPD" >&2; exit 1; }
[ -r /etc/ppp/options ] || {
    echo "Apple pppd requires /etc/ppp/options to exist." >&2
    echo "CJ must explicitly create an empty root-owned file before this test." >&2
    exit 1
}

case "${1:-}" in
--libusb)
    [ "$#" -eq 1 ] || { echo "usage: $0 [--libusb|/dev/cu.usbmodem...]" >&2; exit 1; }
    TMP=$(mktemp -d /private/tmp/t6040-ppp-host.XXXXXX)
    BRIDGE="$TMP/t6040-usb-bulk-pty"
    cc -O2 -Wall -Wextra \
       "$ROOT/scripts/t6040-usb-bulk-pty.c" -o "$BRIDGE" \
       -I/opt/homebrew/include/libusb-1.0 \
       -L/opt/homebrew/lib -lusb-1.0 -lpthread
    "$BRIDGE" >"$TMP/pty" 2>"$TMP/bridge.log" &
    BRIDGE_PID=$!
    for _ in $(jot 100); do
        [ -s "$TMP/pty" ] && break
        kill -0 "$BRIDGE_PID" 2>/dev/null || {
            cat "$TMP/bridge.log" >&2
            exit 1
        }
        sleep 0.1
    done
    [ -s "$TMP/pty" ] || { echo "timed out waiting for libusb PTY" >&2; exit 1; }
    TTY=$(sed -n '1p' "$TMP/pty")
    echo "libusb bridge: $TTY"
    cat "$TMP/bridge.log" >&2
    ;;
/dev/*)
    [ "$#" -eq 1 ] || { echo "usage: $0 [--libusb|/dev/cu.usbmodem...]" >&2; exit 1; }
    TTY=$1
    [ -c "$TTY" ] || { echo "not a character device: $TTY" >&2; exit 1; }
    ;;
*)
    echo "usage: $0 [--libusb|/dev/cu.usbmodem...]" >&2
    exit 1
    ;;
esac

echo "starting host PPP on $TTY: 10.42.0.1 <-> 10.42.0.2"
sudo "$PPPD" "$TTY" 115200 \
    10.42.0.1:10.42.0.2 \
    local noauth nodetach debug nocrtscts \
    lcp-echo-interval 5 lcp-echo-failure 3
