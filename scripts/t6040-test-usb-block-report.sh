#!/bin/sh
# Mocked tests for t6040-usb-block-report.sh (ticket 4001). Builds a fake sysfs
# tree and a regular file standing in for the stick; touches no real device.
# Run under the BusyBox that ships in the target initramfs, for example:
#   podman run --rm -v "$PWD/scripts:/s:ro" alpine:3.22 sh /s/t6040-test-usb-block-report.sh
set -u
R=${0%/*}/t6040-usb-block-report.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0

# mk SECTORS VENDOR PRODUCT SERIAL CONTROLLER REMOVABLE NAME
mk() {
    usb=$T/sys/devices/platform/soc/$5/xhci-hcd.0.auto/usb1/1-1
    dev=$usb/1-1:1.0/host0/target0:0:0/0:0:0:0
    mkdir -p "$dev" "$T/sys/block/$7/holders" "$T/sys/block/$7/${7}1/holders" "$T/dev"
    printf '%s\n' "$2" >"$usb/idVendor"; printf '%s\n' "$3" >"$usb/idProduct"
    printf '%s\n' "$4" >"$usb/serial"; echo 480 >"$usb/speed"
    echo "$6" >"$T/sys/block/$7/removable"; echo "$1" >"$T/sys/block/$7/size"
    ln -s "$dev" "$T/sys/block/$7/device"
    echo 2048 >"$T/sys/block/$7/${7}1/start"; echo $(($1 - 2048 - 33)) >"$T/sys/block/$7/${7}1/size"
    dd if=/dev/urandom of="$T/dev/$7" bs=512 count="$1" 2>/dev/null
}
reset() { rm -rf "$T/sys" "$T/dev"; : >"$T/mounts"; }
run() {
    T6040_REPORT_SYSFS=$T/sys T6040_REPORT_DEV=$T/dev T6040_REPORT_MOUNTS=$T/mounts \
        T6040_REPORT_TEST=1 sh "$R" 0781 55fd 03043930012326064731 4096 >"$T/out" 2>&1
}
expect() {  # expect ok|stop NAME [PATTERN]
    run; rc=$?
    if { [ "$1" = ok ] && [ $rc -eq 0 ] && grep -q T6040_USB_BLOCK_REPORT_OK "$T/out"; } ||
       { [ "$1" = stop ] && [ $rc -ne 0 ] && ! grep -q T6040_USB_BLOCK_REPORT_OK "$T/out" &&
         grep -q "STOP: .*${3:-}" "$T/out"; }; then
        pass=$((pass + 1)); echo "PASS $2"
    else
        fail=$((fail + 1)); echo "FAIL $2 (rc=$rc)"; sed 's/^/    /' "$T/out"
    fi
}
good() { mk 4096 0781 55fd 03043930012326064731 392280000.usb 1 sda; }

reset; good; expect ok happy-path
grep -q '^range gpt-backup lba=4063 count=33 ' "$T/out" && grep -q '^partition sda1 start=2048' "$T/out" &&
    grep -q '^range sda1-head lba=2048 count=8 ' "$T/out" && pass=$((pass + 1)) && echo "PASS report-ranges" ||
    { fail=$((fail + 1)); echo "FAIL report-ranges"; }
# The report must not change the device.
before=$(sha256sum "$T/dev/sda"); run; after=$(sha256sum "$T/dev/sda")
[ "$before" = "$after" ] && pass=$((pass + 1)) && echo "PASS device-unchanged" || { fail=$((fail + 1)); echo "FAIL device-unchanged"; }

reset; mk 4096 0781 55fd WRONGSERIAL 392280000.usb 1 sda; expect stop wrong-serial "no removable"
reset; mk 4096 0781 5581 03043930012326064731 392280000.usb 1 sda; expect stop wrong-product "no removable"
reset; mk 4096 abcd 55fd 03043930012326064731 392280000.usb 1 sda; expect stop wrong-vendor "no removable"
reset; mk 8192 0781 55fd 03043930012326064731 392280000.usb 1 sda; expect stop wrong-size "no removable"
reset; mk 4096 0781 55fd 03043930012326064731 392280000.usb 0 sda; expect stop not-removable "no removable"
reset; mk 4096 0781 55fd 03043930012326064731 3a2280000.usb 1 sda; expect stop wrong-controller "no removable"
reset; good; mkdir -p "$T/sys/class/nvme/nvme0"; expect stop nvme-present "NVMe"
reset; good; echo "$T/dev/sda1 /mnt vfat ro 0 0" >"$T/mounts"; expect stop partition-mounted "mounted"
reset; good; echo "$T/dev/sda /mnt vfat ro 0 0" >"$T/mounts"; expect stop disk-mounted "mounted"
reset; good; mkdir -p "$T/sys/block/sda/sda1/holders/dm-0"; expect stop held-by-dm "held"
reset; good; mk 4096 0781 55fd 03043930012326064731 392280000.usb 1 sdb; expect stop two-matches "more than one"
reset; good; rm "$T/dev/sda"; expect stop node-missing "missing"
reset; good; dd if=/dev/zero of="$T/dev/sda" bs=512 count=100 2>/dev/null; expect stop short-device "short read"
reset; good; T6040_REPORT_TEST=0 T6040_REPORT_SYSFS=$T/sys T6040_REPORT_DEV=$T/dev T6040_REPORT_MOUNTS=$T/mounts \
    sh "$R" 0781 55fd 03043930012326064731 4096 >"$T/out" 2>&1
grep -q 'STOP: .*not a block device' "$T/out" && pass=$((pass + 1)) && echo "PASS regular-file-refused-outside-tests" ||
    { fail=$((fail + 1)); echo "FAIL regular-file-refused-outside-tests"; cat "$T/out"; }
sh "$R" 0781 55fd "" 4096 >"$T/out" 2>&1; grep -q 'STOP: serial must be pinned' "$T/out" && pass=$((pass + 1)) && echo "PASS empty-serial" || { fail=$((fail + 1)); echo "FAIL empty-serial"; }
sh "$R" 0781 55FD x 4096 >"$T/out" 2>&1; grep -q 'STOP: vendor/product' "$T/out" && pass=$((pass + 1)) && echo "PASS bad-hex" || { fail=$((fail + 1)); echo "FAIL bad-hex"; }

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
