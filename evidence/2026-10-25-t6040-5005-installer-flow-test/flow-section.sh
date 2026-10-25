fsck_n() {
    out=$(/sbin/fsck.exfat -n $DEV 2>&1); rc=$?
    say "fsck.exfat -n ($1) rc=$rc: $(echo "$out" | $BB tail -1 | $BB cut -c1-200)"
    [ "$rc" -eq 0 ] || stop "p3 exFAT not clean ($1)"
}
wsec() { set -- $($BB cat "$1"); echo "$7"; }   # field 7 = sectors written
# ANS2 rejects NVMe Flush (5006): write-through before the first mount.
echo "write through" >/sys/block/$N/queue/write_cache 2>/dev/null
[ "$($BB cat /sys/block/$N/queue/write_cache)" = "write through" ] || stop 'cannot set write-through'
say "write_cache=write through"
fsck_n before
DISK_W0=$(wsec /sys/block/$N/stat); P_W0=$(wsec /sys/block/$N/$P/stat)
up() { $BB cut -d' ' -f1 /proc/uptime; }
$BB mount -t exfat -o rw $DEV /mnt/linux || stop 'p3 mount rw failed'
DST=/mnt/linux/wallace-root.img
[ ! -e $DST ] || stop "$DST already exists; nothing to install"
$BB rm -f $DST.partial
t0=$(up)
H=$($BB dd if=$SRC bs=4M 2>/dev/null | $BB tee $DST.partial | $BB sha256sum) || stop 'copy failed'
H=${H%% *}
$BB sync
t1=$(up)
[ "$($BB stat -c %s $DST.partial)" = $SRC_BYTES ] || stop 'copy has the wrong size'
say "copied $SRC_BYTES bytes in $t0..$t1 s; source sha256=$H"
$BB umount /mnt/sd || stop 'SD64 would not unmount'
echo 3 >/proc/sys/vm/drop_caches || stop 'drop_caches failed'
G=$($BB sha256sum $DST.partial); G=${G%% *}
say "re-read copy sha256=$G"
[ "$G" = "$H" ] || stop 'copy differs from the source'

# --- adapt: own UUID, 16 GiB -------------------------------------------------
$BB truncate -s $ROOT_BYTES $DST.partial || stop 'truncate failed'
LOOP=$($BB losetup -f) && $BB losetup "$LOOP" $DST.partial || stop 'cannot attach the copy'
e2() { out=$("$@" 2>&1); rc=$?; say "$* rc=$rc: $(echo "$out" | $BB tail -1 | $BB cut -c1-200)"; return $rc; }
e2 e2fsck -fn "$LOOP" || stop 'copy has ext4 errors'
# -p on a clean filesystem changes nothing but the last-check time, which
# tune2fs -U and resize2fs require.
e2 e2fsck -fp "$LOOP" || stop 'e2fsck -fp failed'
e2 tune2fs -U $ROOT_UUID "$LOOP" || stop 'tune2fs -U failed'
e2 resize2fs "$LOOP" || stop 'resize2fs failed'
e2 e2fsck -fn "$LOOP" || stop 'grown root has ext4 errors'
[ "$($BB findfs UUID=$ROOT_UUID 2>/dev/null)" = "$LOOP" ] || stop 'new UUID not visible'
B=$($BB blockdev --getsize64 "$LOOP")
[ "$B" = $ROOT_BYTES ] || stop "loop size $B"
$BB losetup -d "$LOOP" || stop 'cannot detach the copy'
LOOP=

# --- commit ---------------------------------------------------------------------
$BB mv $DST.partial $DST || stop 'rename failed'
$BB sync
$BB umount /mnt/linux || stop 'p3 would not unmount'
fsck_n final
[ "$(others)" = "$OTHERS_BEFORE" ] || stop 'a read-only partition or namespace saw I/O'
DISK_DW=$(( $(wsec /sys/block/$N/stat) - DISK_W0 ))
P_DW=$(( $(wsec /sys/block/$N/$P/stat) - P_W0 ))
say "sectors written: disk=$DISK_DW p3=$P_DW"
[ "$DISK_DW" = "$P_DW" ] || stop 'writes outside p3 on nvme0n1'
say "PASS installed wallace-root.img bytes=$ROOT_BYTES uuid=$ROOT_UUID source_sha256=$H others_unchanged=yes"
