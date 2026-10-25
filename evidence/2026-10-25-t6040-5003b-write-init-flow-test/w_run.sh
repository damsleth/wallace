apk add -q exfatprogs util-linux sgdisk >/dev/null 2>&1
mount -t devtmpfs none /dev 2>/dev/null; mkdir -p /mnt/linux
mkdir -p /sbin; cp /t/iw/sbin/fsck.exfat /sbin/fsck.exfat
BB=/t/iw/bin/busybox
losetup -D 2>/dev/null; rm -f /tmp/p.img; truncate -s 3G /tmp/p.img
L=$(losetup -f --show -b 4096 -P /tmp/p.img); N=${L#/dev/}
# GPT offset logic test (4K logical blocks, p3 in slot 2)
sgdisk -n1:6:+2000 -t1:AF0A -n2:0:+4000 -t2:AF0A -n3:0:+700000 -t3:0700 -u3:EA0DA6DB-2935-49CB-A996-B982DD646F24 -n4:0:+2000 -t4:AF0A $L >/dev/null
partprobe $L 2>/dev/null; sleep 1
hex() { $BB dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | $BB hexdump -v -e '1/1 "%02x"'; }
LBS=$(cat /sys/block/$N/queue/logical_block_size); E=$((LBS * 2 + 2 * 128))
echo "LBS=$LBS type=$(hex $L $E 16) guid=$(hex $L $((E+16)) 16)  (expect a2a0d0eb… / dba60dea3529cb49a996b982dd646f24)"
echo "first/last LBA bytes: $(hex $L $((E+32)) 16)"; sgdisk -i3 $L | grep -E 'First|Last|unique'
# flow test on a clean exFAT
mkfs.exfat -L linux -c 128K ${L}p3 >/dev/null; DEV=${L}p3; P=${N}p3
run() { ( MODE=$1; TAG=$2; WC=$3; say() { echo "  $*"; }; stop() { echo "  STOP: $*"; $BB umount /mnt/linux 2>/dev/null; exit 3; }
    others() { echo same; }; OTHERS_BEFORE=same; pstat() { $BB cat /sys/block/$N/$P/stat | $BB tr -s ' '; }
    . /t/w_flow.sh; echo "  (fell through)" ); echo "  exit=$?"; }
echo "== write r2 through"; run write r2 through 2>&1 | cut -c1-260
echo "== write r2 again (must refuse)"; run write r2 "" 2>&1 | cut -c1-260
echo "== verify r2"; run verify r2 "" 2>&1 | cut -c1-260
echo "== write r3 write-back"; run write r3 "" 2>&1 | cut -c1-260
echo "== corrupt r3 then verify (must STOP)"; mount -t exfat $DEV /mnt/linux; printf X | dd of=/mnt/linux/wallace-write-test-r3/pattern.bin bs=1 seek=12345 conv=notrunc 2>/dev/null; umount /mnt/linux; run verify r3 "" 2>&1 | cut -c1-260
losetup -d $L 2>/dev/null
