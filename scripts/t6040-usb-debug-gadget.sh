#!/bin/sh
# Composite USB gadget on the device-mode DFU port: CDC-ACM (serial console to the
# host Mac) + CDC-NCM (ethernet). The ACM gives M4-side visibility over the tether
# (macOS makes /dev/cu.usbmodem*), which we lacked. Ticket 173 debug aid.
mount -t configfs none /sys/kernel/config 2>/dev/null
G=/sys/kernel/config/usb_gadget/g1
mkdir -p "$G" 2>/dev/null || exit 0
cd "$G"
echo 0x1d6b > idVendor; echo 0x0104 > idProduct; echo 0x0200 > bcdUSB
echo 0xEF > bDeviceClass; echo 0x02 > bDeviceSubClass; echo 0x01 > bDeviceProtocol  # IAD composite
mkdir -p strings/0x409; echo wallace > strings/0x409/manufacturer
echo t6040-debug > strings/0x409/product; echo J22GYCN4YG > strings/0x409/serialnumber
mkdir -p configs/c.1/strings/0x409; echo "ACM+NCM" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower
mkdir -p functions/acm.GS0
mkdir -p functions/ncm.usb0
ln -sf functions/acm.GS0  configs/c.1/ 2>/dev/null
ln -sf functions/ncm.usb0 configs/c.1/ 2>/dev/null
UDC=$(ls /sys/class/udc 2>/dev/null | grep 382280000 | head -1); [ -z "$UDC" ] && UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
echo "$UDC" > UDC 2>/dev/null
sleep 1
# a login shell on the ACM gadget console + assign the NCM IP
for n in /sys/class/net/usb* /sys/class/net/ncm*; do
  [ -e "$n" ] && { I=$(basename "$n"); ip addr add 10.42.0.2/24 dev "$I" 2>/dev/null; ip link set "$I" up 2>/dev/null; }
done
setsid sh -c 'exec /sbin/getty -n -l /bin/sh 115200 ttyGS0 vt100' >/dev/null 2>&1 &
