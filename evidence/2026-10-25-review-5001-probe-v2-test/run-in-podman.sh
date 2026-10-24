
apk add -q sgdisk exfatprogs util-linux e2fsprogs >/dev/null 2>&1
mount -t devtmpfs none /dev 2>/dev/null
BB=/b/busybox
say() { echo "$*" | awk '{print length($0)": "$0}'; }
park() { echo PARKED; }
mkimg() { # name layout
  losetup -D 2>/dev/null; rm -f /tmp/d.img; truncate -s 700M /tmp/d.img
}
runcase() { # NAME  (expects $L set)
  N=${L#/dev/}
  sed "s#/dev/nvme0n1#$L#g; s#nvme0n1#$N#g; s#/sys/block/$N/stat#/sys/block/$N/stat#" /t/t_section.sh > /tmp/p.sh
  echo "=== $1"; ( . /tmp/p.sh ) 2>&1
}
# case 1: decoy + linux exFAT labelled linux
truncate -s 700M /tmp/d.img
sgdisk -n1:2048:+100M -t1:AF0A -c1:decoy -n2:0:+400M -t2:0700 -c2:linux /tmp/d.img >/dev/null
L=$(losetup -fP --show /tmp/d.img); sleep 1; mkfs.exfat -L linux ${L}p2 >/dev/null
runcase "case1 label=linux"; 
losetup -d $L 2>/dev/null
# case 2: exFAT without label
sgdisk -Z /tmp/d.img >/dev/null 2>&1; truncate -s 0 /tmp/d.img; truncate -s 700M /tmp/d.img
sgdisk -n1:2048:+400M -t1:0700 -c1:x /tmp/d.img >/dev/null
L=$(losetup -fP --show /tmp/d.img); sleep 1; mkfs.exfat ${L}p1 >/dev/null
runcase "case2 exFAT no label"; losetup -d $L 2>/dev/null
# case 3: no exFAT (ext4 only)
truncate -s 0 /tmp/d.img; truncate -s 700M /tmp/d.img
sgdisk -n1:2048:+400M -t1:8300 -c1:e /tmp/d.img >/dev/null
L=$(losetup -fP --show /tmp/d.img); sleep 1; mkfs.ext4 -q ${L}p1
runcase "case3 no exFAT"; losetup -d $L 2>/dev/null
# case 4: two exFAT, different labels
truncate -s 0 /tmp/d.img; truncate -s 700M /tmp/d.img
sgdisk -n1:2048:+200M -t1:0700 -c1:a -n2:0:+200M -t2:0700 -c2:linux /tmp/d.img >/dev/null
L=$(losetup -fP --show /tmp/d.img); sleep 1; mkfs.exfat -L other ${L}p1 >/dev/null; mkfs.exfat -L linux ${L}p2 >/dev/null
runcase "case4 two exFAT"; losetup -d $L 2>/dev/null
