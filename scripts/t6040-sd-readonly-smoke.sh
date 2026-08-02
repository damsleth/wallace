#!/bin/sh
# Fail-closed GL9755 + exFAT read-only smoke for the maintainer's SD64 fixture.
set -eu

PCI_DEV=/sys/bus/pci/devices/0000:02:00.0
MOUNT_DIR=/mnt/sd-ro
PART=/dev/mmcblk0p1
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

i=0
while [ "$i" -lt 30 ] && [ ! -b "$PART" ]; do
	i=$((i + 1))
	sleep 1
done
[ -b "$PART" ] || { echo "STOP: inserted card or partition $PART is missing"; exit 1; }

echo "== GL9755/MMC evidence =="
printf 'PCI: %s:%s class %s driver %s\n' \
	"$(cat "$PCI_DEV/vendor")" "$(cat "$PCI_DEV/device")" \
	"$(cat "$PCI_DEV/class")" "$(basename "$(readlink "$PCI_DEV/driver")")"
ls -l "$PCI_DEV/iommu_group"
ls -l /dev/mmcblk*
cat /sys/class/block/mmcblk0/uevent
cat /sys/class/block/mmcblk0p1/uevent
dmesg | grep -Ei 'pcie|17a0|9755|sdhci|mmc|DART' | tail -120

BLKID=$(blkid "$PART")
echo "$BLKID"
case "$BLKID" in
	*'LABEL="SD64"'*) ;;
	*) echo "STOP: $PART is not the maintainer-provided SD64 fixture"; exit 1 ;;
esac
case "$BLKID" in
	*'TYPE="exfat"'*) ;;
	*) echo "STOP: SD64 is not exFAT"; exit 1 ;;
esac

mkdir -p "$MOUNT_DIR"
mount -t exfat -o ro "$PART" "$MOUNT_DIR"
MOUNTED=1
OPTS=$(awk -v d="$PART" -v m="$MOUNT_DIR" '$1 == d && $2 == m { print $4 }' /proc/mounts)
echo "mount options: $OPTS"
echo "$OPTS" | grep -Eq '(^|,)ro(,|$)' || { echo "STOP: mount is not read-only"; exit 1; }

echo "== SD64 listing (read-only) =="
ls -la "$MOUNT_DIR"
FIRST_FILE=$(find "$MOUNT_DIR" -xdev -type f -print -quit)
[ -n "$FIRST_FILE" ] || { echo "STOP: SD64 contains no regular file to hash"; exit 1; }
echo "== SHA-256 of first regular file =="
sha256sum "$FIRST_FILE"

umount "$MOUNT_DIR"
MOUNTED=0
if awk -v m="$MOUNT_DIR" '$2 == m { found = 1 } END { exit !found }' /proc/mounts; then
	echo "STOP: clean umount did not remove $MOUNT_DIR"
	exit 1
fi
fault_gate
echo "PASS: GL9755 probed, SD64 exFAT mounted read-only, listed, hashed, and cleanly unmounted"
