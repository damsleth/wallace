#!/bin/sh
# Minimal pure CDC-ACM gadget on the device-mode DFU port -> a serial console to
# the host Mac (macOS binds CDC-ACM; it does that for m1n1's proxy gadget). This
# gives M4-side visibility over the tether that ECM/NCM did not. A getty on
# ttyGS0 provides an interactive login. Ticket 173 debug channel.
mount -t configfs none /sys/kernel/config 2>/dev/null
G=/sys/kernel/config/usb_gadget/g1
mkdir -p "$G" 2>/dev/null || exit 0
cd "$G"
echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0200 > bcdUSB
echo 0x02 > bDeviceClass       # Communications Device Class (like a classic CDC-ACM)
echo 0x00 > bDeviceSubClass
echo 0x00 > bDeviceProtocol
mkdir -p strings/0x409
echo wallace     > strings/0x409/manufacturer
echo t6040-acm   > strings/0x409/product
echo J22GYCN4YG  > strings/0x409/serialnumber
mkdir -p configs/c.1/strings/0x409
echo "ACM console" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower
mkdir -p functions/acm.GS0
ln -sf functions/acm.GS0 configs/c.1/ 2>/dev/null
UDC=$(ls /sys/class/udc 2>/dev/null | grep 382280000 | head -1); [ -z "$UDC" ] && UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
[ -z "$UDC" ] && exit 0
# The configfs UDC bind can block IN-KERNEL indefinitely when dwc3 is wedged
# (observed after chainload handoff from m1n1's live gadget). This script used
# to run as a sequential ::sysinit: entry, so a wedged bind froze the whole
# boot at the Asahi logo -- no getty, no X. Bound the write.
timeout 10 sh -c "echo '$UDC' > '$G/UDC'" 2>/dev/null || exit 0
sleep 1
# interactive root shell on the ACM console
setsid sh -c 'exec /sbin/getty -n -l /bin/sh 115200 ttyGS0 vt100' >/dev/null 2>&1 &
