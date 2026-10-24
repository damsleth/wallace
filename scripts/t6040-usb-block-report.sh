#!/bin/sh
# Read-only identity reporter for the right-port USB stick (ticket 109; built
# in ticket 4001). Runs on the M4 after ticket 305 has brought up VBUS.
#
# It proves which device it is looking at before it reads anything, then
# reads and hashes only fixed sector ranges. It never mounts, writes, runs
# fsck, changes partitions, or opens a device for writing: every byte goes
# through `dd if=... of=/dev/stdout`, and nothing else touches the device.
#
# usage: t6040-usb-block-report.sh VENDOR PRODUCT SERIAL SECTORS
#   e.g. t6040-usb-block-report.sh 0781 55fd 03043930012326064731 240328704
# Exit 0 with a report on stdout only if exactly one device matches all gates.
#
# T6040_REPORT_SYSFS / _DEV / _MOUNTS relocate /sys, /dev and /proc/mounts and
# T6040_REPORT_TEST=1 accepts regular files as devices -- for the host tests in
# t6040-test-usb-block-report.sh only.
set -u

VERSION=t6040-usb-block-report-v1
SYS=${T6040_REPORT_SYSFS:-/sys}
DEV=${T6040_REPORT_DEV:-/dev}
MOUNTS=${T6040_REPORT_MOUNTS:-/proc/mounts}
# Right-port dwc3/xHCI from the live ticket-108 boot (io mem 0x392280000).
CONTROLLER=392280000.usb

stop() { echo "STOP: $*"; exit 1; }
[ "$#" -eq 4 ] || stop "usage: $0 VENDOR PRODUCT SERIAL SECTORS"
want_vendor=$1 want_product=$2 want_serial=$3 want_sectors=$4
case "$want_vendor$want_product" in *[!0-9a-f]*|'') stop "vendor/product must be lower-case hex" ;; esac
case "$want_sectors" in *[!0-9]*|'') stop "sectors must be decimal" ;; esac
[ -n "$want_serial" ] || stop "serial must be pinned"

echo "reporter=$VERSION"
self=$(sha256sum "$0" 2>/dev/null) && echo "reporter_sha256=${self%% *}"

# Ticket 109: the internal SSD must not be visible to this boot at all.
for n in "$SYS"/class/nvme/* "$SYS"/block/nvme*; do
    [ -e "$n" ] && stop "NVMe device present ($n); the 109 image must not expose NVMe"
done

# Exactly one candidate may match every identity gate.
match=""
for b in "$SYS"/block/sd*; do
    [ -e "$b" ] || continue
    name=${b##*/}
    [ "$(cat "$b/removable" 2>/dev/null)" = 1 ] || continue
    [ "$(cat "$b/size" 2>/dev/null)" = "$want_sectors" ] || continue
    path=$(readlink -f "$b/device" 2>/dev/null) || continue
    case "$path" in */"$CONTROLLER"/xhci-hcd.*) ;; *) continue ;; esac
    ok=0 a=$path
    while [ -n "$a" ] && [ "$a" != / ] && [ "$a" != . ]; do
        if [ -f "$a/idVendor" ]; then
            [ "$(cat "$a/idVendor")" = "$want_vendor" ] &&
                [ "$(cat "$a/idProduct" 2>/dev/null)" = "$want_product" ] &&
                [ "$(cat "$a/serial" 2>/dev/null)" = "$want_serial" ] && ok=1
            break
        fi
        a=${a%/*}
    done
    [ "$ok" = 1 ] || continue
    [ -z "$match" ] || stop "more than one device matches ($match, $name)"
    match=$name usbdev=$a
done
[ -n "$match" ] || stop "no removable right-port device matches $want_vendor:$want_product serial $want_serial with $want_sectors sectors"

node=$DEV/$match
if [ "${T6040_REPORT_TEST:-0}" = 1 ]; then
    [ -f "$node" ] || [ -b "$node" ] || stop "$node missing"
else
    [ -b "$node" ] || stop "$node is not a block device"
fi
# Nothing on it may be mounted or held by another driver (dm, md, loop).
grep -Eq "^$DEV/$match[0-9]* " "$MOUNTS" && stop "$match or a partition is mounted"
for h in "$SYS/block/$match"/holders/* "$SYS/block/$match"/"$match"*/holders/*; do
    [ -e "$h" ] && stop "$match is held by ${h##*/}"
done
echo "device=$match"
echo "usb=$want_vendor:$want_product serial=$want_serial"
echo "usb_path=${usbdev#"$SYS"}"
echo "speed=$(cat "$usbdev/speed" 2>/dev/null || echo unknown)"
echo "sectors=$want_sectors"

# hash_range LABEL FIRST_SECTOR COUNT -- one dd read, nothing else.
hash_range() {
    h=$(dd if="$node" of=/dev/stdout bs=512 skip="$2" count="$3" 2>/dev/null | sha256sum) ||
        stop "read of $1 failed"
    got=$(dd if="$node" of=/dev/stdout bs=512 skip="$2" count="$3" 2>/dev/null | wc -c)
    [ "$got" -eq $(($3 * 512)) ] || stop "short read of $1 ($got bytes)"
    echo "range $1 lba=$2 count=$3 sha256=${h%% *}"
}
hash_range mbr-or-pmbr 0 1
hash_range gpt-primary 1 33
hash_range gpt-backup $((want_sectors - 33)) 33
for p in "$SYS/block/$match/$match"[0-9]*; do
    [ -e "$p/start" ] || continue
    start=$(cat "$p/start") size=$(cat "$p/size")
    echo "partition ${p##*/} start=$start sectors=$size"
    hash_range "${p##*/}-head" "$start" 8
done
echo "T6040_USB_BLOCK_REPORT_OK"
