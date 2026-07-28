#!/bin/sh
# USB-tether ethernet: build a PURE CDC-ECM gadget via configfs on the M4's
# device-mode DFU port so it appears as an ethernet NIC to the host Mac over the
# proxy cable (ticket 173). No VBUS/host-mode needed.
#
# g_ether (legacy USB_ETH) is deliberately NOT in the kernel: its RNDIS-first
# composite enumerated on macOS as "RNDIS/Ethernet Gadget" but macOS does not
# support RNDIS, so no interface was created. A pure ecm.usb0 gadget is what
# macOS binds. M4 = 10.42.0.2/24; on the Mac set the new CDC interface to
# 10.42.0.1/24 then ping 10.42.0.2. Log: /var/log/ecm-gadget.log.
LOG=/var/log/ecm-gadget.log
{
echo "== ecm-gadget (pure configfs CDC-ECM) =="
mount -t configfs none /sys/kernel/config 2>/dev/null
echo "== UDCs =="; ls /sys/class/udc 2>/dev/null
G=/sys/kernel/config/usb_gadget/g1
mkdir -p "$G" || { echo "no usb_gadget configfs (USB_GADGET/CONFIGFS builtin?)"; exit 1; }
cd "$G"
echo 0x1d6b > idVendor          # Linux Foundation
echo 0x0104 > idProduct         # Multifunction Composite Gadget
echo 0x0200 > bcdUSB
mkdir -p strings/0x409
echo wallace   > strings/0x409/manufacturer
echo t6040-ecm > strings/0x409/product
echo J22GYCN4YG > strings/0x409/serialnumber
mkdir -p configs/c.1/strings/0x409
echo "CDC NCM" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower
# macOS binds CDC-NCM (AppleUSBDeviceNCM*), NOT CDC-ECM (AppleUSBCDCCompositeDevice
# stayed !matched in the 2026-07-28 smoke). Present a pure NCM function; fall back
# to ECM if the kernel lacks the ncm function. host/dev MAC auto-assigned.
if mkdir -p functions/ncm.usb0 2>/dev/null; then
    FN=ncm.usb0
else
    mkdir -p functions/ecm.usb0; FN=ecm.usb0
fi
echo "gadget function: $FN"
ln -sf functions/$FN configs/c.1/ 2>/dev/null
# bind the tether UDC (usb_drd0 @ 382280000); else first UDC
UDC=$(ls /sys/class/udc 2>/dev/null | grep 382280000 | head -1)
[ -z "$UDC" ] && UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
echo "binding UDC: $UDC"
echo "$UDC" > UDC 2>/dev/null && echo "bound OK" || echo "UDC bind FAILED"
sleep 1
# bring up the M4-side interface
for n in /sys/class/net/usb*; do
  [ -e "$n" ] || continue
  I=$(basename "$n")
  ip link set "$I" up 2>/dev/null || ifconfig "$I" up 2>/dev/null
  ip addr add 10.42.0.2/24 dev "$I" 2>/dev/null || ifconfig "$I" 10.42.0.2 netmask 255.255.255.0 up 2>/dev/null
  echo "assigned 10.42.0.2 to $I"
done
echo "== state =="; ip addr 2>/dev/null | grep -E "usb|10.42" || ifconfig 2>/dev/null | grep -A1 usb
echo "host Mac: set the new CDC interface to 10.42.0.1/24, then ping 10.42.0.2"
} > "$LOG" 2>&1
