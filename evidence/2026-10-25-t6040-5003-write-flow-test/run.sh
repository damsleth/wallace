apk add -q exfatprogs util-linux >/dev/null
mount -t devtmpfs none /dev; losetup -D 2>/dev/null; mkdir -p /mnt/linux /tmp/x
truncate -s 3G /tmp/p.img; L=$(losetup -f --show -b 4096 /tmp/p.img); mkfs.exfat -L linux -c 128K $L >/dev/null
export PATH=/x:$PATH; mkdir -p /x; for a in $(/t/bb/bin/busybox --list); do ln -sf /t/bb/bin/busybox /x/$a; done
mkdir -p /sbin; cp /t/bb/sbin/fsck.exfat /sbin/fsck.exfat 2>/dev/null
run() { # mode
  ( BB=/t/bb/bin/busybox; DEV=$L; P=x; MODE=$1
    say() { echo "  $*"; }; stop() { echo "  STOP: $*"; $BB umount /mnt/linux 2>/dev/null; exit 3; }
    park() { echo "  PARKED"; $BB umount /mnt/linux 2>/dev/null; exit 0; }
    pstat() { cat /sys/block/${L#/dev/}/stat | tr -s ' '; }
    others() { echo same; }; OTHERS_BEFORE=same
    . /t/flow.sh; echo "  (fell through)" ); echo "  exit=$?"
}
echo "== write"; run write
echo "== write again (must refuse)"; run write
echo "== verify"; run verify
echo "== corrupt one byte, verify (must STOP)"; mount -t exfat $L /mnt/linux; printf 'X' | dd of=/mnt/linux/wallace-write-test/pattern.bin bs=1 seek=12345 conv=notrunc 2>/dev/null; umount /mnt/linux; run verify
losetup -d $L
