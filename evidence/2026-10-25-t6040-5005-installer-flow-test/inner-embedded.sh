BB=/bin/busybox; PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH
set -o pipefail
say() { echo "  $*"; }
LOOP=
stop() { echo "  STOP: $*"; [ -z "$LOOP" ] || $BB losetup -d "$LOOP"; $BB umount /mnt/linux 2>/dev/null; exit 3; }
others() { echo same; }; OTHERS_BEFORE=same
ROOT_UUID=988d97b4-06ba-40d7-8f70-7899bb6fa297
SRC=/t5/wallace-root.img.xz
EXP=$($BB cut -d' ' -f1 /t5/wallace-root.img.sha256)
. /t/flow-section-embedded.sh
echo "  (fell through)"
