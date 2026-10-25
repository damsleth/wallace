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
H=$($BB xzcat $SRC | $BB tee $DST.partial | $BB sha256sum) || stop 'copy failed'
H=${H%% *}
$BB sync
t1=$(up)
[ "$($BB stat -c %s $DST.partial)" = $ROOT_BYTES ] || stop 'copy has the wrong size'
say "wrote $ROOT_BYTES bytes in $t0..$t1 s; sha256=$H expected=$EXP"
[ "$H" = "$EXP" ] || stop 'decompressed image differs from the pinned hash'
echo 3 >/proc/sys/vm/drop_caches || stop 'drop_caches failed'
G=$($BB sha256sum $DST.partial); G=${G%% *}
say "re-read copy sha256=$G"
[ "$G" = "$EXP" ] || stop 'copy on p3 differs from the pinned hash'

# --- check ---------------------------------------------------------------------
LOOP=$($BB losetup -f) && $BB losetup -r "$LOOP" $DST.partial || stop 'cannot attach the copy'
e2() { out=$("$@" 2>&1); rc=$?; say "$* rc=$rc: $(echo "$out" | $BB tail -1 | $BB cut -c1-200)"; return $rc; }
e2 e2fsck -fn "$LOOP" || stop 'root image has ext4 errors'
[ "$($BB findfs UUID=$ROOT_UUID 2>/dev/null)" = "$LOOP" ] || stop 'root UUID not visible'
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
say "PASS installed wallace-root.img bytes=$ROOT_BYTES uuid=$ROOT_UUID sha256=$H others_unchanged=yes"
