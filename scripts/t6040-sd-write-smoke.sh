#!/bin/sh
# Bounded write/fsync/remount verification for SD64. Run only under ticket B.
set -eu

PART=/dev/mmcblk0p1
PCI_DEV=/sys/bus/pci/devices/0000:02:00.0
MOUNT_DIR=/mnt/sd-rw
TEST_FILE=$MOUNT_DIR/t6040-sd-write-test.txt
EXPECTED='Project Wallace GL9755 verified write'
EXPECTED_SHA=be6ae148beafbeee5599324a6704b5d6a192b406bd56107886933eeaa86933ca
MOUNTED=0

cleanup()
{
	if [ "$MOUNTED" = 1 ]; then
		umount "$MOUNT_DIR" || true
	fi
}
trap cleanup EXIT HUP INT TERM

fault_gate()
{
	if dmesg | grep -Eiq 'SError|DART.*fault|IOMMU.*fault|Unhandled fault|Internal error|Kernel panic'; then
		echo "STOP: PCIe/DART/kernel fault signature present"
		dmesg | grep -Ei 'SError|DART.*fault|IOMMU.*fault|Unhandled fault|Internal error|Kernel panic' | tail -20
		exit 1
	fi
}

[ "${T6040_SD_WRITE_APPROVED:-}" = SD64 ] || {
	echo "STOP: set T6040_SD_WRITE_APPROVED=SD64 only under approved ticket B"
	exit 1
}
fault_gate
[ -d "$PCI_DEV" ] || { echo "STOP: GL9755 0000:02:00.0 absent"; exit 1; }
[ "$(cat "$PCI_DEV/vendor")" = 0x17a0 ] || { echo "STOP: wrong PCI vendor"; exit 1; }
[ "$(cat "$PCI_DEV/device")" = 0x9755 ] || { echo "STOP: wrong PCI device"; exit 1; }
[ -L "$PCI_DEV/driver" ] || { echo "STOP: GL9755 has no bound driver"; exit 1; }
[ "$(basename "$(readlink "$PCI_DEV/driver")")" = sdhci-pci ] || {
	echo "STOP: GL9755 bound to unexpected driver"
	ls -l "$PCI_DEV/driver"
	exit 1
}
[ -L "$PCI_DEV/iommu_group" ] || { echo "STOP: GL9755 lacks DART/IOMMU group"; exit 1; }
[ -b "$PART" ] || { echo "STOP: $PART missing"; exit 1; }
BLKID=$(blkid "$PART")
echo "$BLKID"
case "$BLKID" in
	*'LABEL="SD64"'*'TYPE="exfat"'*) ;;
	*) echo "STOP: device is not the SD64 exFAT fixture"; exit 1 ;;
esac

mkdir -p "$MOUNT_DIR"
mount -t exfat -o rw "$PART" "$MOUNT_DIR"
MOUNTED=1
OPTS=$(awk -v d="$PART" -v m="$MOUNT_DIR" '$1 == d && $2 == m { print $4 }' /proc/mounts)
echo "rw mount options: $OPTS"
echo "$OPTS" | grep -Eq '(^|,)rw(,|$)' || { echo "STOP: mount is not read-write"; exit 1; }
[ ! -e "$TEST_FILE" ] || { echo "STOP: refusing to overwrite existing $TEST_FILE"; exit 1; }

set -C
printf '%s\n' "$EXPECTED" > "$TEST_FILE"
set +C
# BusyBox sync FILE uses fsync(2); sync the containing directory as well so
# the exFAT directory entry is durable before unmount.
sync "$TEST_FILE"
sync "$MOUNT_DIR"
WRITTEN_SHA=$(sha256sum "$TEST_FILE" | awk '{print $1}')
echo "written sha256: $WRITTEN_SHA"
[ "$WRITTEN_SHA" = "$EXPECTED_SHA" ] || { echo "STOP: freshly written SHA-256 is unexpected"; exit 1; }

umount "$MOUNT_DIR"
MOUNTED=0
mount -t exfat -o ro "$PART" "$MOUNT_DIR"
MOUNTED=1
OPTS=$(awk -v d="$PART" -v m="$MOUNT_DIR" '$1 == d && $2 == m { print $4 }' /proc/mounts)
echo "remount options: $OPTS"
echo "$OPTS" | grep -Eq '(^|,)ro(,|$)' || { echo "STOP: verification remount is not read-only"; exit 1; }
[ "$(cat "$TEST_FILE")" = "$EXPECTED" ] || { echo "STOP: content mismatch after remount"; exit 1; }
VERIFIED_SHA=$(sha256sum "$TEST_FILE" | awk '{print $1}')
[ "$VERIFIED_SHA" = "$EXPECTED_SHA" ] || { echo "STOP: SHA-256 mismatch after remount"; exit 1; }
echo "verified sha256: $VERIFIED_SHA"

umount "$MOUNT_DIR"
MOUNTED=0
fault_gate
echo "PASS: wrote, fsynced, unmounted, remounted read-only, and verified $TEST_FILE"
