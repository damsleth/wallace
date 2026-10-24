# u32/u8 little-endian readers on a read-only device.
u32() { v=$($BB dd if="$1" bs=1 skip="$2" count=4 2>/dev/null | $BB od -An -tu4); echo ${v##* }; }
u8() { v=$($BB dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | $BB od -An -tu1); echo ${v##* }; }
hexline() { $BB dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | $BB hexdump -v -e '16/1 "%02x" " "'; }

# GPT header and the first 8 entries (128 bytes each, from LBA 2).
gpt=$($BB dd if=/dev/nvme0n1 bs=512 count=34 2>/dev/null | $BB sha256sum)
say "gpt-lba0-33 sha256=${gpt%% *}"
say "gpt-header: $(hexline /dev/nvme0n1 512 92)"
e=0
while [ "$e" -lt 8 ]; do
    say "gpt-entry$e: $(hexline /dev/nvme0n1 $((1024 + e * 128)) 128)"
    e=$((e + 1))
done

nexfat=0
for p in /sys/block/nvme0n1/nvme0n1p*; do
    n=${p##*/}
    say "part $n start=$($BB cat $p/start) size=$($BB cat $p/size) $($BB grep -E '^(PARTN|PARTNAME)=' $p/uevent | $BB tr '\n' ' ')"
    dev=/dev/$n
    oem=$($BB dd if="$dev" bs=1 skip=3 count=8 2>/dev/null)
    [ "$oem" = "EXFAT   " ] || { say "part $n not exFAT"; continue; }
    nexfat=$((nexfat + 1))
    bs=$($BB dd if="$dev" bs=512 count=1 2>/dev/null | $BB sha256sum)
    say "exfat $n bootsector sha256=${bs%% *}"
    say "exfat $n bootsector[64..119]: $(hexline "$dev" 64 56)"
    heap=$(u32 "$dev" 88); root=$(u32 "$dev" 96)
    bps=$(u8 "$dev" 108); spc=$(u8 "$dev" 109)
    flags=$($BB dd if="$dev" bs=1 skip=106 count=2 2>/dev/null | $BB od -An -tu2)
    say "exfat $n heap=$heap rootcluster=$root bpsshift=$bps spcshift=$spc volumeflags=${flags##* }"
    # Root directory: label entry (type 0x83) is normally first; dump 8 entries.
    off=$(( (heap + ((root - 2) << spc)) << bps ))
    say "exfat $n rootdir-offset=$off"
    say "exfat $n rootdir[0..127]: $(hexline "$dev" "$off" 128)"
    say "exfat $n rootdir[128..255]: $(hexline "$dev" $((off + 128)) 128)"
done
[ "$nexfat" -ge 1 ] || { say 'STOP: no exFAT partition found'; park; }
say "exfat-partitions=$nexfat"
say "stats after: $($BB cat /sys/block/nvme0n1/stat)"
say 'IDENTITY-DONE'
