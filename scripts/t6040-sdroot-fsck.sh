#!/bin/sh
# Repair only the known SD64 exFAT fixture and its known ext4 loop image.
# Run from the ticket-215 bootstrap image after exact approval and review.
set -u

PART=/dev/mmcblk0p1
SD=/mnt/sd-fsck
LOOP=
MODE=${T6040_SD_FSCK_MODE:-repair}

stop() { echo "STOP: $*"; exit 1; }
cleanup() {
    rc=$?
    trap - EXIT INT TERM
    sync
    if [ -n "$LOOP" ] && ! losetup -d "$LOOP" 2>/dev/null; then
        echo "STOP: cleanup could not detach $LOOP"
        rc=1
    fi
    if mountpoint -q "$SD" && ! umount "$SD"; then
        echo "STOP: cleanup could not unmount $SD"
        rc=1
    fi
    exit "$rc"
}
trap cleanup EXIT INT TERM

[ "${T6040_SD_FSCK_APPROVED:-}" = SD64 ] || \
    stop "set T6040_SD_FSCK_APPROVED=SD64 only under approved ticket 215"
case "$MODE" in repair|check) ;; *) stop "T6040_SD_FSCK_MODE must be repair or check" ;; esac
[ -b "$PART" ] || stop "$PART is missing"
[ "$(blkid -s LABEL -o value "$PART")" = SD64 ] || stop "wrong SD label"
[ "$(blkid -s TYPE -o value "$PART")" = exfat ] || stop "SD64 is not exFAT"
mountpoint -q "$SD" && stop "$SD is already mounted"
grep -q " $PART " /proc/mounts && stop "$PART is already mounted"

echo "== exFAT read-only assessment =="
/usr/sbin/fsck.exfat -n -v "$PART"
exfat_rc=$?
echo "assessment rc=$exfat_rc"
case "$exfat_rc" in
    0|4) ;;
    *) stop "exFAT assessment failed operationally with rc=$exfat_rc" ;;
esac

if [ "$MODE" = check ]; then
    [ "$exfat_rc" -eq 0 ] || stop "exFAT read-only check returned $exfat_rc"
    mkdir -p "$SD"
    mount -t exfat -o ro "$PART" "$SD" || stop "cannot mount SD64 read-only"
    [ "$(stat -c %s "$SD/wallace-root.img")" = 6442450944 ] || stop "unexpected root-image size"
    LOOP=$(losetup -f) || stop "no free loop device"
    losetup -r "$LOOP" "$SD/wallace-root.img" || stop "cannot attach root image read-only"
    [ "$(blkid -s UUID -o value "$LOOP")" = 4c41b99c-7747-4688-85a5-397bc5d784a2 ] || \
        stop "unexpected ext4 root UUID"
    [ "$(blkid -s TYPE -o value "$LOOP")" = ext4 ] || stop "root image is not ext4"
    echo "== ext4 read-only assessment =="
    e2fsck -f -n "$LOOP"
    ext4_rc=$?
    echo "assessment rc=$ext4_rc"
    [ "$ext4_rc" -eq 0 ] || stop "ext4 read-only check returned $ext4_rc"
    losetup -d "$LOOP" || stop "cannot detach $LOOP"
    LOOP=
    umount "$SD" || stop "cannot cleanly unmount SD64"
    trap - EXIT INT TERM
    echo "PASS: SD64 exFAT and the ext4 root are clean; no repair was attempted"
    exit 0
fi

echo "== exFAT automatic repair =="
/usr/sbin/fsck.exfat -p -v "$PART"
rc=$?
[ "$rc" -le 1 ] || stop "fsck.exfat returned $rc; no forced repair attempted"
echo "== exFAT post-repair assessment =="
/usr/sbin/fsck.exfat -n -v "$PART" || stop "exFAT is not clean after automatic repair"

mkdir -p "$SD"
mount -t exfat -o rw "$PART" "$SD" || stop "cannot mount repaired SD64"
[ "$(stat -c %s "$SD/wallace-root.img")" = 6442450944 ] || stop "unexpected root-image size"
LOOP=$(losetup -f) || stop "no free loop device"
losetup "$LOOP" "$SD/wallace-root.img" || stop "cannot attach root image"
[ "$(blkid -s UUID -o value "$LOOP")" = 4c41b99c-7747-4688-85a5-397bc5d784a2 ] || \
    stop "unexpected ext4 root UUID"
[ "$(blkid -s TYPE -o value "$LOOP")" = ext4 ] || stop "root image is not ext4"

echo "== ext4 read-only assessment =="
e2fsck -f -n "$LOOP"
ext4_rc=$?
echo "assessment rc=$ext4_rc"
case "$ext4_rc" in
    0|4) ;;
    *) stop "ext4 assessment failed operationally with rc=$ext4_rc" ;;
esac
echo "== ext4 automatic repair =="
e2fsck -f -p "$LOOP"
rc=$?
[ "$rc" -le 1 ] || stop "e2fsck returned $rc; no forced repair attempted"
echo "== ext4 post-repair assessment =="
e2fsck -f -n "$LOOP" || stop "ext4 root is not clean after automatic repair"

sync
losetup -d "$LOOP" || stop "cannot detach $LOOP"
LOOP=
umount "$SD" || stop "cannot cleanly unmount SD64"
echo "== exFAT final post-unmount assessment =="
/usr/sbin/fsck.exfat -n -v "$PART" || \
    stop "exFAT is not clean after the ext4 repair cycle"
trap - EXIT INT TERM
echo "PASS: SD64 exFAT and the ext4 root passed post-repair read-only checks"
