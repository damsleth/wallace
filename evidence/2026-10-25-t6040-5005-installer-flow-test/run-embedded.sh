# Embedded-image installer flow test (scaled 1 GiB test image) plus a
# full-size decode of the real artifact with the installer's own busybox.
set -u
apk add -q exfatprogs e2fsprogs sgdisk util-linux xz >/dev/null 2>&1
mount -t devtmpfs none /dev 2>/dev/null
W=/var/tmp/w5005e; rm -rf $W; mkdir -p $W/r
cleanup_w() {
    for i in 1 2 3; do
        for m in $(awk -v w="$W" '$2 ~ "^"w {print $2}' /proc/mounts | sort -r); do umount -l "$m" 2>/dev/null; done
    done
    if awk -v w="$W" '$2 ~ "^"w {f=1} END {exit !f}' /proc/mounts; then echo "REFUSING rm: mounts remain"; return 1; fi
    rm -rf "$W"
}
(cd $W/r && gzip -dc /h/initramfs-install-a.cpio.gz | cpio -id 2>/dev/null)
echo "== full-size decode of the shipped image with the installer's busybox"
got=$(chroot $W/r /bin/busybox sh -c '/bin/busybox xzcat /wallace-root.img.xz | /bin/busybox sha256sum' | cut -d' ' -f1)
echo "  decoded sha256=$got pinned=$(cut -c1-64 $W/r/wallace-root.img.sha256)"
mkdir -p $W/r/t $W/r/t5; cp /t/inner-embedded.sh /t/flow-section-embedded.sh $W/r/t/
truncate -s 1073741824 $W/small.ext4
mke2fs -q -t ext4 -U 988d97b4-06ba-40d7-8f70-7899bb6fa297 -d $W/r/usr/share $W/small.ext4
xz -T0 --check=crc32 -c $W/small.ext4 > $W/r/t5/wallace-root.img.xz
sha256sum $W/small.ext4 | cut -d' ' -f1 > $W/r/t5/wallace-root.img.sha256
rm -f $W/small.ext4
truncate -s 3G $W/nvme.img
L=$(losetup -f --show -b 4096 -P $W/nvme.img); N=${L#/dev/}
sgdisk -n1:6:+2000 -t1:AF0A -n2:0:+4000 -t2:AF0A -n3:0:+700000 -t3:0700 -n4:0:+2000 -t4:AF0A $L >/dev/null
partprobe $L; sleep 1
mkfs.exfat -L linux -c 128K ${L}p3 >/dev/null
for d in dev proc sys; do mount --rbind /$d $W/r/$d; done
mkdir -p $W/r/mnt/linux
run() { chroot $W/r /bin/busybox env N=$N P=${N}p3 DEV=${L}p3 ROOT_BYTES=1073741824 \
        /bin/busybox sh /t/inner-embedded.sh 2>&1 | cut -c1-260; }
echo "== install (scaled)"; run
echo "== install again (must refuse)"; run
cleanup_w
losetup -d $L
