fsck_n() {
    out=$(/sbin/fsck.exfat -n "$DEV" 2>&1); rc=$?
    say "fsck.exfat -n ($1) rc=$rc: $(echo "$out" | $BB tail -1 | $BB cut -c1-200)"
    [ "$rc" -eq 0 ] || stop "exFAT not clean ($1)"
}
pstat() { $BB cat /sys/block/$N/$P/stat | $BB tr -s ' '; }
# Field 7 of a block stat line is sectors written.
wsec() { set -- $($BB cat "$1"); echo "$7"; }
DISK_W0=$(wsec /sys/block/$N/stat); P_W0=$(wsec /sys/block/$N/$P/stat)
fsck_n before
say "p3 stats before: $(pstat)"
D=/mnt/linux/wallace-write-test${TAG:+-$TAG}
if [ "$WC" = through ]; then
    echo "write through" >/sys/block/$N/queue/write_cache || stop 'cannot set write_cache'
fi
WCNOW="$($BB cat /sys/block/$N/queue/write_cache)"
[ -z "$WC" ] || [ "$WCNOW" = "write through" ] || stop "write_cache is '$WCNOW'"
say "dir=$D write_cache=$WCNOW fua=$($BB cat /sys/block/$N/queue/fua)"
up() { $BB cut -d' ' -f1 /proc/uptime; }

if [ "$MODE" = write ]; then
    $BB mount -t exfat -o rw "$DEV" /mnt/linux || stop 'mount rw failed'
    [ ! -e "$D" ] || stop "$D already exists; use nvmewrite=verify"
    $BB mkdir "$D" || stop 'mkdir failed'
    t0=$(up)
    $BB dd if=/dev/urandom of="$D/pattern.bin" bs=1M count=1024 conv=fsync 2>/dev/null || stop 'write failed'
    $BB sync
    t1=$(up)
    say "wrote 1073741824 bytes in $t0..$t1 s (uptime)"
    H=$($BB sha256sum "$D/pattern.bin"); H=${H%% *}
    echo "$H  pattern.bin" >"$D/pattern.sha256" && $BB sync || stop 'hash file write failed'
    say "write sha256=$H"
    $BB umount /mnt/linux || stop 'umount after write failed'
    fsck_n after-write
fi

# Read back from the device: drop every cached page and buffer first.
$BB sync
echo 3 >/proc/sys/vm/drop_caches || stop 'drop_caches failed'
$BB mount -t exfat -o ro "$DEV" /mnt/linux || stop 'mount ro failed'
[ -f "$D/pattern.bin" ] && [ -f "$D/pattern.sha256" ] || stop 'test file missing'
EXP=$($BB cut -d' ' -f1 "$D/pattern.sha256")
t0=$(up)
GOT=$($BB sha256sum "$D/pattern.bin"); GOT=${GOT%% *}
t1=$(up)
say "read back 1073741824 bytes in $t0..$t1 s; sha256=$GOT expected=$EXP"
$BB umount /mnt/linux || stop 'umount after read failed'
[ "$GOT" = "$EXP" ] || stop 'data mismatch'
fsck_n final
say "p3 stats after: $(pstat)"
[ "$(others)" = "$OTHERS_BEFORE" ] || stop 'a read-only partition or namespace saw I/O'
DISK_DW=$(( $(wsec /sys/block/$N/stat) - DISK_W0 ))
P_DW=$(( $(wsec /sys/block/$N/$P/stat) - P_W0 ))
say "sectors written: disk=$DISK_DW p3=$P_DW"
[ "$DISK_DW" = "$P_DW" ] || stop 'writes outside p3 on nvme0n1'
say "PASS mode=$MODE bytes=1073741824 sha256=$GOT others_unchanged=yes write_cache=${WCNOW#write }"
