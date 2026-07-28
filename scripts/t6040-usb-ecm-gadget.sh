#!/bin/sh
# Bring up a USB CDC-ECM gadget on the M4's device-mode tether port (usb_drd0,
# 382280000.usb) so the machine appears as a NIC to the host Mac over the same
# cable used for m1n1 proxy/DebugUSB. No VBUS/host-mode needed. Ticket 173.
#
# Static link on 10.42.0.0/24: M4 = 10.42.0.2, host Mac = 10.42.0.1 (assign on
# the Mac's new CDC interface). Logs to /var/log/ecm-gadget.log.
LOG=/var/log/ecm-gadget.log
{
echo "== ecm-gadget $(date 2>/dev/null) =="
mount -t configfs none /sys/kernel/config 2>/dev/null
G=/sys/kernel/config/usb_gadget/g1
mkdir -p "$G" || { echo "no usb_gadget configfs (USB_GADGET/CONFIGFS builtin?)"; exit 1; }
cd "$G"
echo 0x1d6b > idVendor        # Linux Foundation
echo 0x0104 > idProduct       # Multifunction Composite Gadget
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB
mkdir -p strings/0x409
echo "wallace"    > strings/0x409/manufacturer
echo "t6040-ecm"  > strings/0x409/product
echo "J22GYCN4YG" > strings/0x409/serialnumber
mkdir -p configs/c.1/strings/0x409
echo "CDC ECM" > configs/c.1/strings/0x409/configuration
echo 250       > configs/c.1/MaxPower
mkdir -p functions/ecm.usb0
ln -sf functions/ecm.usb0 configs/c.1/ 2>/dev/null
echo "== available UDCs =="; ls /sys/class/udc
# Prefer the tether port (usb_drd0 @ 382280000); else first UDC.
UDC=$(ls /sys/class/udc | grep 382280000 | head -1)
[ -z "$UDC" ] && UDC=$(ls /sys/class/udc | head -1)
echo "binding UDC: $UDC"
echo "$UDC" > UDC || echo "UDC bind FAILED"
sleep 1
ip link set usb0 up 2>/dev/null || ifconfig usb0 up 2>/dev/null
ip addr add 10.42.0.2/24 dev usb0 2>/dev/null || ifconfig usb0 10.42.0.2 netmask 255.255.255.0 up 2>/dev/null
echo "== usb0 state =="; ip addr show usb0 2>/dev/null || ifconfig usb0 2>/dev/null
echo "M4 is 10.42.0.2; on the host Mac, set the new CDC/RNDIS interface to 10.42.0.1/24, then ping 10.42.0.2"
} > "$LOG" 2>&1
