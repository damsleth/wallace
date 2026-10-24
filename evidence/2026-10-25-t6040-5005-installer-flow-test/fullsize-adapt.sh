# Full-size adapt sequence (6 GiB -> 16 GiB) with the installer's own e2fsprogs,
# on a sparse plain file (no exFAT): proves the resize scale, not the copy.
apk add -q e2fsprogs e2fsprogs-extra >/dev/null 2>&1
mount -t devtmpfs none /dev 2>/dev/null
W=/var/tmp/w5005f; rm -rf $W; mkdir -p $W/r; (cd $W/r && gzip -dc /h/initramfs-install-a.cpio.gz | cpio -id 2>/dev/null)
cleanup_w() {  # never rm a tree with live mounts (BusyBox umount has no -R)
    for i in 1 2 3; do
        for m in $(awk -v w="$W" '$2 ~ "^"w {print $2}' /proc/mounts | sort -r); do umount -l "$m" 2>/dev/null; done
    done
    if awk -v w="$W" '$2 ~ "^"w {f=1} END {exit !f}' /proc/mounts; then
        echo "REFUSING rm: mounts remain under $W"; return 1
    fi
    rm -rf "$W"
}
truncate -s 6442450944 $W/r/img
mke2fs -q -t ext4 -U 4c41b99c-7747-4688-85a5-397bc5d784a2 -d $W/r/usr $W/r/img
echo "source: $(dumpe2fs -h $W/r/img 2>/dev/null | grep -E '^Filesystem features|^Block count|^Reserved GDT' | tr '\n' ';')"
for d in dev proc sys; do mount --rbind /$d $W/r/$d; done
chroot $W/r /bin/busybox sh -c '
  BB=/bin/busybox; PATH=/usr/sbin:/sbin:/bin
  $BB truncate -s 17179869184 /img; L=$($BB losetup -f); $BB losetup $L /img
  for c in "e2fsck -fn $L" "e2fsck -fp $L" "tune2fs -U 988d97b4-06ba-40d7-8f70-7899bb6fa297 $L" "resize2fs $L" "e2fsck -fn $L"; do
    t0=$($BB cut -d" " -f1 /proc/uptime); out=$($c 2>&1); rc=$?; t1=$($BB cut -d" " -f1 /proc/uptime)
    echo "  $c rc=$rc ($t0..$t1 s): $(echo "$out" | $BB tail -1)"; done
  echo "  findfs: $($BB findfs UUID=988d97b4-06ba-40d7-8f70-7899bb6fa297) loop=$L size=$($BB blockdev --getsize64 $L)"
  $BB losetup -d $L'
echo "result: $(dumpe2fs -h $W/r/img 2>/dev/null | grep -E '^Filesystem UUID|^Block count|^Filesystem state' | tr '\n' ';')"
cleanup_w
