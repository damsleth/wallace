#!/bin/busybox sh
# SPDX-License-Identifier: MIT
# Source-only USB-root identity gate. CJ Damsleth <kim@damsleth.no>
# No findfs, mounts, writable opens, repair or root= device-path fallback.
# The init caller supplies fixed /sys, /dev and its immutable identity file.
# Explicit fixture roots and image mode exist for host tests on regular files.

usb_root_cmd() { "${USBROOT_BB:-/bin/busybox}" "$@"; }
usb_root_fail() { echo "usb-root-select: STOP: $*" >&2; return 1; }

usb_root_select() (
    [ "$#" -eq 5 ] || { usb_root_fail "need sysfs, devroot, identity, metadata helper and mode"; exit 1; }
    sys=$1 devroot=$2 identity=$3 metadata=$4 mode=$5
    case "$mode" in disk|image) ;; *) usb_root_fail "invalid mode"; exit 1 ;; esac
    [ -f "$identity" ] && [ ! -L "$identity" ] || { usb_root_fail "missing regular identity file"; exit 1; }
    # No eval or sourcing of configuration. Unknown/duplicate fields fail.
    seen='|'; format= disk_guid= partuuid= fsuuid= media_bytes= layout_bytes=
    usb_vendor= usb_product= usb_serial= usb_route= usb_controller= removable=
    while IFS='=' read -r key value || [ -n "$key" ]; do
        case "$key" in ''|'#'*) continue ;; esac
        case "$seen" in *"|$key|"*) usb_root_fail "duplicate identity field $key"; exit 1 ;; esac
        seen=$seen$key'|'
        [ -n "$value" ] || { usb_root_fail "empty identity field $key"; exit 1; }
        case "$key" in
            format) format=$value ;;
            disk_guid) disk_guid=$value ;;
            partuuid) partuuid=$value ;;
            fsuuid) fsuuid=$value ;;
            media_bytes) media_bytes=$value ;;
            layout_bytes) layout_bytes=$value ;;
            usb_vendor) usb_vendor=$value ;;
            usb_product) usb_product=$value ;;
            usb_serial) usb_serial=$value ;;
            usb_route) usb_route=$value ;;
            usb_controller) usb_controller=$value ;;
            removable) removable=$value ;;
            *) usb_root_fail "unknown identity field $key"; exit 1 ;;
        esac
    done <"$identity"
    [ "$format" = t6040-usb-root-identity-v1 ] && [ "$removable" = 1 ] &&
        [ "$usb_controller" = 392280000.usb ] || { usb_root_fail "wrong identity format, controller or removable policy"; exit 1; }
    for value in "$disk_guid" "$partuuid" "$fsuuid"; do
        printf '%s\n' "$value" | usb_root_cmd grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' ||
            { usb_root_fail "missing or invalid UUID"; exit 1; }
    done
    for value in "$usb_vendor" "$usb_product"; do
        printf '%s\n' "$value" | usb_root_cmd grep -Eq '^[0-9a-f]{4}$' ||
            { usb_root_fail "missing or invalid USB ID"; exit 1; }
    done
    [ -n "$usb_serial" ] || { usb_root_fail "USB serial must be pinned"; exit 1; }
    # A directly connected stick, not a guessed route through an extra hub.
    printf '%s\n' "$usb_route" | usb_root_cmd grep -Eq '^[1-9][0-9]*$' ||
        { usb_root_fail "missing or non-direct USB route"; exit 1; }
    for value in "$media_bytes" "$layout_bytes"; do
        printf '%s\n' "$value" | usb_root_cmd grep -Eq '^[1-9][0-9]*$' && [ "${#value}" -le 16 ] ||
            { usb_root_fail "missing or excessive media/layout size"; exit 1; }
    done
    [ "$media_bytes" -ge "$layout_bytes" ] && [ $((media_bytes % 512)) -eq 0 ] ||
        { usb_root_fail "invalid pinned capacity"; exit 1; }
    # Reject alternate root= specifications even when the correct disk exists.
    roots=0
    for token in $(usb_root_cmd cat "$sys/../proc/cmdline" 2>/dev/null); do
        case "$token" in
            root=*) roots=$((roots + 1)); [ "$token" = "root=PARTUUID=$partuuid" ] ||
                { usb_root_fail "root= must match the pinned PARTUUID"; exit 1; } ;;
            rootfstype=*) [ "$token" = rootfstype=ext4 ] ||
                { usb_root_fail "only ext4 root is supported"; exit 1; } ;;
        esac
    done
    [ "$roots" -eq 1 ] || { usb_root_fail "need exactly one root= selector"; exit 1; }
    matches=0 selected= disk_number= partition_number=
    [ -r "$sys/../proc/self/mountinfo" ] || { usb_root_fail "mount state unavailable"; exit 1; }
    for entry in "$sys"/class/block/sd*; do
        [ -e "$entry" ] || continue
        name=${entry##*/}
        printf '%s\n' "$name" | usb_root_cmd grep -Eq '^sd[a-z]+$' || continue
        [ ! -e "$entry/partition" ] || continue
        path=$(usb_root_cmd readlink -f "$entry") || continue
        case "$path" in "$sys"/devices/*/392280000.usb/*) ;; *) continue ;; esac
        [ "$(usb_root_cmd cat "$entry/removable" 2>/dev/null)" = 1 ] || continue
        sectors=$(usb_root_cmd cat "$entry/size" 2>/dev/null) || continue
        [ "$sectors" = "$((media_bytes / 512))" ] || continue
        ancestor=$path found=0
        while [ "$ancestor" != "$sys/devices" ] && [ "$ancestor" != / ]; do
            if [ -f "$ancestor/idVendor" ]; then
                [ "$(usb_root_cmd cat "$ancestor/idVendor")" = "$usb_vendor" ] &&
                    [ "$(usb_root_cmd cat "$ancestor/idProduct" 2>/dev/null)" = "$usb_product" ] &&
                    [ "$(usb_root_cmd cat "$ancestor/serial" 2>/dev/null)" = "$usb_serial" ] &&
                    [ "$(usb_root_cmd cat "$ancestor/devpath" 2>/dev/null)" = "$usb_route" ] && found=1
                break
            fi
            ancestor=${ancestor%/*}
        done
        [ "$found" -eq 1 ] || continue
        # Bind partition1 to this exact physical disk, not just a matching name.
        partition=$(usb_root_cmd readlink -f "$sys/class/block/${name}1") || continue
        [ "${partition%/*}" = "$path" ] &&
            [ "$(usb_root_cmd cat "$sys/class/block/${name}1/partition" 2>/dev/null)" = 1 ] || continue
        case "$mode" in
            disk) [ -b "$devroot/$name" ] && [ -b "$devroot/${name}1" ] || continue ;;
            image) [ -f "$devroot/$name" ] && [ -f "$devroot/${name}1" ] || continue ;;
        esac
        [ ! -L "$devroot/$name" ] && [ ! -L "$devroot/${name}1" ] || continue
        dn=$(usb_root_cmd cat "$entry/dev" 2>/dev/null) || continue
        pn=$(usb_root_cmd cat "$sys/class/block/${name}1/dev" 2>/dev/null) || continue
        for value in "$dn" "$pn"; do
            printf '%s\n' "$value" | usb_root_cmd grep -Eq '^[0-9]+:[0-9]+$' ||
                { usb_root_fail "device number unavailable"; exit 1; }
        done
        mounted_rc=0
        usb_root_cmd awk -v d="$dn" -v p="$pn" \
            '$3 == d || $3 == p { found=1 } END { exit !found }' \
            "$sys/../proc/self/mountinfo" || mounted_rc=$?
        case "$mounted_rc" in
            0) usb_root_fail "matching disk/partition is already mounted"; exit 1 ;;
            1) ;;
            *) usb_root_fail "mount state inspection failed"; exit 1 ;;
        esac
        matches=$((matches + 1)); selected=$name; disk_number=$dn; partition_number=$pn
    done
    # Status3 means discovery is not ready; all metadata errors are status1
    # and must never be retried by init as if the stick had not appeared.
    [ "$matches" -ne 0 ] || { usb_root_fail "expected one matching right-port stick, found 0"; exit 3; }
    [ "$matches" -eq 1 ] || { usb_root_fail "expected one matching right-port stick, found $matches"; exit 1; }
    # No block reads occur until all matching candidates have been counted.
    if [ "$mode" = disk ]; then
        # Match the partition node too. The C helper separately binds the
        # whole disk's descriptor to its reviewed sysfs device number.
        hex=$(usb_root_cmd stat -c '%t:%T' "$devroot/${selected}1") || exit 1
        hm=${hex%:*}; hn=${hex#*:}
        case "$hm:$hn" in *[!0-9a-fA-F:]*) usb_root_fail "invalid partition device number"; exit 1 ;; esac
        [ "$((0x$hm)):$((0x$hn))" = "$partition_number" ] ||
            { usb_root_fail "partition node differs from sysfs identity"; exit 1; }
        set -- --device-number "$disk_number"
    else
        set --
    fi
    meta=$("$metadata" "--$mode" "$devroot/$selected" --disk-guid "$disk_guid" \
        --partuuid "$partuuid" --fsuuid "$fsuuid" --media-bytes "$media_bytes" \
        --layout-bytes "$layout_bytes" "$@") || exit 1
    first=$(printf '%s\n' "$meta" | usb_root_cmd sed -n 's/^partition_first_lba=//p')
    last=$(printf '%s\n' "$meta" | usb_root_cmd sed -n 's/^partition_last_lba=//p')
    # A valid on-disk GPT does not prove the kernel partition node reflects it
    # (for example after stale partition discovery). Bind that view before fsck
    # or mount can operate on a different byte range.
    [ "$first" = 2048 ] &&
        [ "$(usb_root_cmd cat "$sys/class/block/${selected}1/start" 2>/dev/null)" = "$first" ] &&
        [ "$(usb_root_cmd cat "$sys/class/block/${selected}1/size" 2>/dev/null)" = "$((last - first + 1))" ] ||
        { usb_root_fail "kernel partition extent differs from verified GPT"; exit 1; }
    printf '%s\n' "$meta"
    printf 'usb_root_device=%s/%s1\n' "$devroot" "$selected"
)
