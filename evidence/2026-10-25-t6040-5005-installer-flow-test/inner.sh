# Runs chrooted in the extracted installer initramfs: its own BusyBox 1.37,
# e2fsprogs 1.47.4 and static fsck.exfat. Variables are the script's, scaled.
BB=/bin/busybox; PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH
set -o pipefail
say() { echo "  $*"; }
LOOP=
stop() { echo "  STOP: $*"; [ -z "$LOOP" ] || $BB losetup -d "$LOOP"; $BB umount /mnt/linux 2>/dev/null; $BB umount /mnt/sd 2>/dev/null; exit 3; }
others() { echo same; }; OTHERS_BEFORE=same
SRC=/mnt/sd/wallace-root.img
ROOT_UUID=988d97b4-06ba-40d7-8f70-7899bb6fa297
. /t/flow-section.sh
echo "  (fell through)"
