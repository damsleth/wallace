#!/bin/sh
# Linux USB gadget for a direct PPP link over the first ACM function.
#
# Descriptor shape deliberately matches the ticket-183 discriminator.  The
# target pppd uses ttyGS0; ttyGS1 stays idle to retain m1n1's two-function
# topology.  The host can use a native /dev/cu.usbmodem* or the exact
# product-gated libusb PTY bridge.

LOG=/var/log/m1n1-acm-ppp-gadget.log
{
echo "== m1n1-shaped dual ACM PPP gadget =="
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
echo "dual ACM PPP" > configs/c.1/strings/0x409/configuration
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

[ -x /usr/sbin/pppd ] || { echo "pppd missing"; exit 1; }
setsid /usr/sbin/pppd /dev/ttyGS0 115200 \
  10.42.0.2:10.42.0.1 \
  local noauth nodetach debug nocrtscts persist maxfail 0 \
  lcp-echo-interval 5 lcp-echo-failure 3 \
  >/var/log/pppd-tether.log 2>&1 &
echo "pppd pid: $!"
} > "$LOG" 2>&1
