# Outer harness (alpine:3.22, rootful, privileged). /h = installer initramfs dir,
# /t = this directory. Scaled: source $SRC_BYTES, target $ROOT_BYTES.
set -u
apk add -q exfatprogs e2fsprogs sgdisk util-linux >/dev/null 2>&1
mount -t devtmpfs none /dev 2>/dev/null
W=/var/tmp/w5005; rm -rf $W; mkdir -p $W/r $W/sdm
cleanup_w() {  # never rm a tree with live mounts (BusyBox umount has no -R)
    for i in 1 2 3; do
        for m in $(awk -v w="$W" '$2 ~ "^"w {print $2}' /proc/mounts | sort -r); do umount -l "$m" 2>/dev/null; done
    done
    if awk -v w="$W" '$2 ~ "^"w {f=1} END {exit !f}' /proc/mounts; then
        echo "REFUSING rm: mounts remain under $W"; return 1
    fi
    rm -rf "$W"
}
(cd $W/r && gzip -dc /h/initramfs-install-a.cpio.gz | cpio -id 2>/dev/null)
mkdir -p $W/r/t; cp /t/inner.sh /t/flow-section.sh $W/r/t/
truncate -s 5G $W/nvme.img
L=$(losetup -f --show -b 4096 -P $W/nvme.img); N=${L#/dev/}
sgdisk -n1:6:+2000 -t1:AF0A -n2:0:+4000 -t2:AF0A -n3:0:+4G -t3:0700 -n4:0:+2000 -t4:AF0A $L >/dev/null
partprobe $L; sleep 1
mkfs.exfat -L linux -c 128K ${L}p3 >/dev/null
truncate -s 2G $W/sd.img; S=$(losetup -f --show $W/sd.img); mkfs.exfat -L SD64 $S >/dev/null
truncate -s $SRC_BYTES $W/src.ext4
mke2fs -q -t ext4 $MKE2FS_OPTS -U 4c41b99c-7747-4688-85a5-397bc5d784a2 -d $W/r $W/src.ext4
echo "source: $(dumpe2fs -h $W/src.ext4 2>/dev/null | grep -E '^Filesystem features')"
mount -t exfat $S $W/sdm && dd if=$W/src.ext4 of=$W/sdm/wallace-root.img bs=4M status=none && umount $W/sdm
rm -f $W/src.ext4
for d in dev proc sys; do mount --rbind /$d $W/r/$d; done
mkdir -p $W/r/mnt/sd $W/r/mnt/linux; mount -t exfat -o ro $S $W/r/mnt/sd
run() { chroot $W/r /bin/busybox env N=$N P=${N}p3 DEV=${L}p3 SRC_BYTES=$SRC_BYTES ROOT_BYTES=$ROOT_BYTES \
        /bin/busybox sh /t/inner.sh 2>&1 | cut -c1-300; }
echo "== install"; run; echo "  exit=$?"
echo "== result: $(mount -t exfat -o ro ${L}p3 $W/sdm && ls -l $W/sdm | tr -s ' ' | grep wallace; \
     e2fsck -fn $W/sdm/wallace-root.img >/dev/null 2>&1; echo e2fsck=$?; \
     dumpe2fs -h $W/sdm/wallace-root.img 2>/dev/null | grep -E '^Filesystem UUID|^Block count'; umount $W/sdm)"
mount -t exfat -o ro $S $W/r/mnt/sd
echo "== install again (must refuse)"; run
umount $W/r/mnt/sd 2>/dev/null
cleanup_w
losetup -d $L $S
