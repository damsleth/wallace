# Does the installer's static fsck.exfat -y clear a set VolumeFlags dirty bit?
apk add -q exfatprogs >/dev/null 2>&1
W=/var/tmp/w5005d; rm -rf $W; mkdir -p $W/r; (cd $W/r && gzip -dc /h/initramfs-install-a.cpio.gz | cpio -id 2>/dev/null)
truncate -s 512M $W/x.img; mkfs.exfat -L linux $W/x.img >/dev/null
printf '\002\000' | dd of=$W/x.img bs=1 seek=106 conv=notrunc 2>/dev/null
f() { $W/r/bin/busybox dd if=$W/x.img bs=1 skip=106 count=2 2>/dev/null | $W/r/bin/busybox od -An -tu2; }
echo "before: VolumeFlags=$(f)"; $W/r/sbin/fsck.exfat -y $W/x.img 2>&1 | tail -1; echo "rc=$?"; echo "after: VolumeFlags=$(f)"
rm -rf $W
