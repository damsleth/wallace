apk add -q sgdisk exfatprogs util-linux >/dev/null
mount -t devtmpfs none /dev
losetup -D 2>/dev/null
truncate -s 600M /tmp/d.img
sgdisk -n1:2048:+100M -t1:AF0A -c1:decoy -n2:0:+400M -t2:0700 -c2:linux /tmp/d.img >/dev/null
L=$(losetup -fP --show /tmp/d.img); N=${L#/dev/}; sleep 2
mkfs.exfat -L linux ${L}p2 >/dev/null
BB=/t/bb/bin/busybox
say() { echo "$*" | awk '{print length($0)": "$0}'; }
sed "s/nvme0n1/$N/g" /t/parse.sh > /tmp/p.sh
. /tmp/p.sh
losetup -d $L
