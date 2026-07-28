#!/bin/sh
# USB-tether ethernet on the M4's device-mode port so it appears as a NIC to the
# host Mac over the proxy/DFU cable — no VBUS/host-mode needed (ticket 173).
#
# The kernel has USB_ETH (g_ether) builtin, which AUTO-BINDS the first device-mode
# UDC at boot and creates a usbN interface. So the primary path is: find that
# interface and give it an IP. If g_ether did not bind (e.g. no free UDC), fall
# back to an explicit configfs ECM gadget on the tether UDC (382280000).
# M4 = 10.42.0.2/24; on the host Mac set the new CDC interface to 10.42.0.1/24.
LOG=/var/log/ecm-gadget.log
IP4=10.42.0.2
setip() {  # $1 = iface
    ip link set "$1" up 2>/dev/null || ifconfig "$1" up 2>/dev/null
    ip addr add "$IP4/24" dev "$1" 2>/dev/null || ifconfig "$1" "$IP4" netmask 255.255.255.0 up 2>/dev/null
    echo "assigned $IP4 to $1"
}
{
echo "== ecm-gadget =="
mount -t configfs none /sys/kernel/config 2>/dev/null
echo "== UDCs =="; ls /sys/class/udc 2>/dev/null
# 1) g_ether auto-bind: wait up to ~5s for a usb* net interface
IFACE=""
i=0; while [ $i -lt 25 ]; do
    for n in /sys/class/net/usb*; do [ -e "$n" ] && IFACE=$(basename "$n") && break; done
    [ -n "$IFACE" ] && break; sleep 0.2; i=$((i+1))
done
if [ -n "$IFACE" ]; then
    echo "g_ether interface: $IFACE"; setip "$IFACE"
else
    # 2) fallback: explicit configfs ECM on the tether UDC
    echo "no g_ether iface; building configfs ECM gadget"
    G=/sys/kernel/config/usb_gadget/g1; mkdir -p "$G" && cd "$G" || { echo "no gadget configfs"; exit 1; }
    echo 0x1d6b > idVendor; echo 0x0104 > idProduct
    mkdir -p strings/0x409; echo wallace > strings/0x409/manufacturer; echo t6040-ecm > strings/0x409/product
    mkdir -p configs/c.1/strings/0x409; echo "CDC ECM" > configs/c.1/strings/0x409/configuration
    mkdir -p functions/ecm.usb0; ln -sf functions/ecm.usb0 configs/c.1/ 2>/dev/null
    UDC=$(ls /sys/class/udc | grep 382280000 | head -1); [ -z "$UDC" ] && UDC=$(ls /sys/class/udc | head -1)
    echo "binding UDC: $UDC"; echo "$UDC" > UDC 2>/dev/null || echo "UDC bind FAILED"
    sleep 1
    for n in /sys/class/net/usb*; do [ -e "$n" ] && setip "$(basename "$n")"; done
fi
echo "== interfaces =="; ip addr 2>/dev/null | grep -E "usb|10.42" || ifconfig 2>/dev/null | grep -A1 usb
echo "M4 is $IP4. On the host Mac: set the new CDC/RNDIS interface to 10.42.0.1/24, then ping $IP4"
} > "$LOG" 2>&1
