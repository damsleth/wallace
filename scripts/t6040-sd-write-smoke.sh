#!/bin/sh
# Bounded write/fsync/remount verification for SD64. Run only under ticket B.
set -eu

PART=/dev/mmcblk0p1
MOUNT_DIR=/mnt/sd-rw
TEST_FILE=$MOUNT_DIR/t6040-sd-write-test.txt
EXPECTED='Project Wallace GL9755 verified write'
MOUNTED=0

cleanup()
{
	if [ "$MOUNTED" = 1 ]; then
		umount "$MOUNT_DIR" || true
	fi
}
trap cleanup EXIT HUP INT TERM

[ "${T6040_SD_WRITE_APPROVED:-}" = SD64 ] || {
	echo "STOP: set T6040_SD_WRITE_APPROVED=SD64 only under approved ticket B"
	exit 1
}
if dmesg | grep -Eiq 'SError|DART.*fault|IOMMU.*fault|Unhandled fault|Internal error|Kernel panic'; then
	echo "STOP: pre-existing PCIe/DART/kernel fault signature"
	exit 1
fi
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

umount "$MOUNT_DIR"
MOUNTED=0
mount -t exfat -o ro "$PART" "$MOUNT_DIR"
MOUNTED=1
OPTS=$(awk -v d="$PART" -v m="$MOUNT_DIR" '$1 == d && $2 == m { print $4 }' /proc/mounts)
echo "remount options: $OPTS"
echo "$OPTS" | grep -Eq '(^|,)ro(,|$)' || { echo "STOP: verification remount is not read-only"; exit 1; }
[ "$(cat "$TEST_FILE")" = "$EXPECTED" ] || { echo "STOP: content mismatch after remount"; exit 1; }
VERIFIED_SHA=$(sha256sum "$TEST_FILE" | awk '{print $1}')
[ "$VERIFIED_SHA" = "$WRITTEN_SHA" ] || { echo "STOP: SHA-256 mismatch after remount"; exit 1; }
echo "verified sha256: $VERIFIED_SHA"

umount "$MOUNT_DIR"
MOUNTED=0
if dmesg | grep -Eiq 'SError|DART.*fault|IOMMU.*fault|Unhandled fault|Internal error|Kernel panic'; then
	echo "STOP: post-write PCIe/DART/kernel fault signature"
	exit 1
fi
echo "PASS: wrote, fsynced, unmounted, remounted read-only, and verified $TEST_FILE"
