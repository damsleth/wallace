#!/bin/sh
# Diagnostic-only Linux USB gadget matching the descriptor *shape* that macOS
# already accepts from m1n1 on this same T6040:
#   - 1209:316d, device class CDC, two independent ACM functions
#   - self-powered, one 500 mA configuration
#
# ConfigFS emits the Linux ACM functional descriptors, so this is not claimed
# to be byte-identical to m1n1. It isolates the device identity, top-level
# class, configuration power flags, and two-function topology in one bounded
# test. ttyGS0 gets a shell; ttyGS1 is left idle, matching m1n1's second pipe.

LOG=/var/log/m1n1-acm-gadget.log
{
echo "== m1n1-shaped dual ACM gadget =="
mount -t configfs none /sys/kernel/config 2>/dev/null
G=/sys/kernel/config/usb_gadget/g1
mkdir -p "$G" || { echo "no usb_gadget configfs"; exit 1; }
cd "$G" || exit 1

echo 0x1209 > idVendor
echo 0x316d > idProduct
echo 0x0200 > bcdUSB
echo 0x0100 > bcdDevice
echo 0x02 > bDeviceClass
echo 0x00 > bDeviceSubClass
echo 0x00 > bDeviceProtocol

mkdir -p strings/0x409
echo "Asahi Linux" > strings/0x409/manufacturer
echo "m1n1-shaped Linux ACM diagnostic" > strings/0x409/product
echo "J22GYCN4YG" > strings/0x409/serialnumber

mkdir -p configs/c.1/strings/0x409
echo "dual ACM" > configs/c.1/strings/0x409/configuration
echo 0xc0 > configs/c.1/bmAttributes
echo 500 > configs/c.1/MaxPower

mkdir -p functions/acm.GS0 functions/acm.GS1
ln -sf functions/acm.GS0 configs/c.1/
ln -sf functions/acm.GS1 configs/c.1/

UDC=$(ls /sys/class/udc 2>/dev/null | grep 382280000 | head -1)
[ -z "$UDC" ] && UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
echo "binding UDC: $UDC"
[ -n "$UDC" ] || { echo "no UDC"; exit 1; }
echo "$UDC" > UDC || { echo "UDC bind failed"; exit 1; }
sleep 1

echo "state: $(cat /sys/class/udc/"$UDC"/state 2>/dev/null)"
echo "function: $(cat /sys/class/udc/"$UDC"/function 2>/dev/null)"
ls -l /dev/ttyGS* 2>/dev/null

setsid sh -c 'exec /sbin/getty -n -l /bin/sh 115200 ttyGS0 vt100' \
  >/dev/null 2>&1 &
} > "$LOG" 2>&1
