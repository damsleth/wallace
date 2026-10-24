#!/bin/sh
# SPDX-License-Identifier: MIT
# Container-only harness. Chroots each real init into a fresh PID namespace.
# Device nodes are dummy stat fixtures. No operation opens their data paths.
set -eu
apk add --no-cache util-linux >/out/apk.log 2>&1
cp /bin/busybox /work/real-busybox
cp -L /lib/ld-musl-aarch64.so.1 /work/loader

cat >/work/busybox-wrapper <<'WRAPPER'
#!/real/bin/busybox sh
R=/real/bin/busybox
app=$1; shift
trace() { echo "$*" >>/trace; }
inject() {
    [ "$( $R cat /inject )" = "$1" ] || return 0
    trace "INJECT $1"; exit 1
}
case "$app" in
    sh) exec "$R" sh "$@" ;;
    mkdir)
        case "$*" in
            '-p /proc /sys /dev /newroot /tmp') inject initial_mkdir ;;
            '-p /newroot/dev /newroot/proc /newroot/sys') inject handoff_mkdir ;;
        esac
        exec "$R" mkdir "$@" ;;
    mount)
        trace "MOUNT $*"
        case "$*" in
            '-t devtmpfs none /dev') inject initial_dev ;;
            '-t proc none /proc') inject initial_proc ;;
            '-t sysfs none /sys') inject initial_sys ;;
            '-t ext4 -o ro,noload /dev/sda1 /newroot')
                inject inspect_mount
                "$R" cp -a /fixture-root/. /newroot/
                echo ro >/root-state
                trace ROOT_RO ;;
            '-t ext4 -o rw /dev/sda1 /newroot')
                inject rw_mount
                "$R" cp -a /fixture-root/. /newroot/
                echo rw >/root-state
                trace ROOT_RW ;;
            '-t devtmpfs none /newroot/dev') inject handoff_dev ;;
            '-t proc none /newroot/proc') inject handoff_proc ;;
            '-t sysfs none /newroot/sys') inject handoff_sys ;;
            '-o remount,ro /newroot')
                inject cleanup_remount
                echo final-ro >/root-state
                trace CLEANUP_RO ;;
            *) trace "FORBIDDEN mount $*"; exit 99 ;;
        esac
        exit 0 ;;
    umount)
        trace "UMOUNT $*"
        case "$*" in
            /newroot)
                if [ "$( $R cat /root-state )" = ro ]; then
                    inject inspect_unmount
                    echo absent >/root-state
                    trace INSPECT_DONE
                    "$R" rm -rf /newroot/*
                else
                    inject cleanup_unmount
                    echo absent >/root-state
                    trace CLEANUP_UNMOUNT
                fi ;;
            /newroot/sys|/newroot/proc|/newroot/dev) ;;
            *) trace "FORBIDDEN umount $*"; exit 99 ;;
        esac
        exit 0 ;;
    loadkmap) trace KEYMAP_LOAD; inject load_keymap; echo yes >/keymap-ready; exit 0 ;;
    sleep)
        if [ "$1" = 3600 ]; then
            trace 'TERMINAL no-shell'
            exec "$R" sleep 60
        fi
        trace DISCOVERY_WAIT
        exit 0 ;;
    setsid)
        trace "TERMINAL rescue keymap=$( $R cat /keymap-ready )"
        exit 0 ;;
    switch_root)
        trace "HANDOFF $*"
        inject switch_root
        trace 'TERMINAL switch-root'
        exit 0 ;;
    poweroff|reboot|halt|modprobe|mdev)
        trace "FORBIDDEN $app $*"; exit 99 ;;
    *) exec "$R" "$app" "$@" ;;
esac
WRAPPER

cat >/work/metadata-stub <<'METADATA'
#!/real/bin/busybox sh
R=/real/bin/busybox
n=$( $R cat /metadata-count ); n=$((n + 1)); echo "$n" >/metadata-count
echo "METADATA $n $*" >>/trace
inj=$( $R cat /inject )
if [ "$inj" = metadata_first ] || { [ "$inj" = metadata_second ] && [ "$n" -eq 2 ]; }; then
    echo "INJECT $inj" >>/trace; exit 1
fi
fs=912d5c4e-7475-4875-a178-52ce5119a703
if [ "$inj" = identity_second ] && [ "$n" -eq 2 ]; then
    echo "INJECT $inj" >>/trace
    fs=11111111-2222-3333-4444-555555555555
fi
echo format=t6040-usb-root-metadata-v1
echo partuuid=e4731abe-3566-4c3a-8019-c8828ca27a5a
echo filesystem_uuid=$fs
echo partition_first_lba=2048
echo partition_last_lba=2097118
echo metadata_gate=PASS
METADATA

cat >/work/fsck-stub <<'FSCK'
#!/real/bin/busybox sh
R=/real/bin/busybox
echo "FSCK $*" >>/trace
[ "$*" = '-f -n /dev/sda1' ] || { echo 'FORBIDDEN fsck arguments' >>/trace; exit 99; }
if [ "$( $R cat /inject )" = fsck ]; then echo 'INJECT fsck' >>/trace; exit 4; fi
exit 0
FSCK
chmod 755 /work/*-wrapper /work/*-stub

make_disk() {
    root=$1 name=$2 minor=$3 usb=$4
    disk=/sys/devices/platform/soc/392280000.usb/usb3/$usb/host0/block/$name
    mkdir -p "$root$disk/${name}1" "$root/sys/class/block"
    parent=$root/sys/devices/platform/soc/392280000.usb/usb3/$usb
    printf '%s\n' 1234 >"$parent/idVendor"
    printf '%s\n' 5678 >"$parent/idProduct"
    printf '%s\n' fixture-stick >"$parent/serial"
    printf '%s\n' 1 >"$parent/devpath"
    echo 1 >"$root$disk/removable"
    echo 2097152 >"$root$disk/size"
    echo "8:$minor" >"$root$disk/dev"
    echo 1 >"$root$disk/${name}1/partition"
    echo "8:$((minor + 1))" >"$root$disk/${name}1/dev"
    echo 2048 >"$root$disk/${name}1/start"
    echo 2095071 >"$root$disk/${name}1/size"
    ln -s "$disk" "$root/sys/class/block/$name"
    ln -s "$disk/${name}1" "$root/sys/class/block/${name}1"
    mknod "$root/dev/$name" b 8 "$minor"
    mknod "$root/dev/${name}1" b 8 "$((minor + 1))"
}

make_fixture() {
    root=$1
    mkdir -p "$root/real/bin" "$root/bin" "$root/sbin" "$root/lib" "$root/etc" "$root/tmp" \
        "$root/proc/self" "$root/proc/sys/kernel" "$root/sys/devices/system/cpu" \
        "$root/dev" "$root/newroot" "$root/opt/wallace" \
        "$root/fixture-root/bin" "$root/fixture-root/sbin" \
        "$root/fixture-root/etc/conf.d" "$root/fixture-root/etc/X11/xorg.conf.d" \
        "$root/fixture-root/etc/init.d" "$root/fixture-root/etc/runlevels/shutdown" \
        "$root/fixture-root/etc/runlevels/boot" "$root/fixture-root/usr/local/sbin"
    cp /work/real-busybox "$root/real/bin/busybox"
    cp /work/loader "$root/lib/ld-musl-aarch64.so.1"
    cp /work/busybox-wrapper "$root/bin/busybox"
    cp /work/metadata-stub "$root/sbin/t6040-usb-root-metadata"
    cp /work/fsck-stub "$root/sbin/e2fsck"
    cp /in/init "$root/init"
    cp /in/select "$root/opt/wallace/t6040-usb-root-select.sh"
    cp /in/keymap "$root/etc/wallace-no.bmap"
    echo 0 >"$root/sys/devices/system/cpu/online"
    echo no >"$root/keymap-ready"
    echo 0 >"$root/metadata-count"
    echo absent >"$root/root-state"
    : >"$root/trace"
    : >"$root/proc/self/mountinfo"
    : >"$root/proc/sys/kernel/printk"
    printf '%s\n' 'maxcpus=1 root=PARTUUID=e4731abe-3566-4c3a-8019-c8828ca27a5a rootfstype=ext4' >"$root/proc/cmdline"
    mknod "$root/dev/tty1" c 1 3
    # tty1 is a null-backed console fixture; no actual VT/UART is opened.
    make_disk "$root" sda 0 3-1
    cat >"$root/etc/wallace-usb-root.identity" <<'IDENTITY'
format=t6040-usb-root-identity-v1
disk_guid=192409a8-fe11-4cbf-9182-14eb737b69a6
partuuid=e4731abe-3566-4c3a-8019-c8828ca27a5a
fsuuid=912d5c4e-7475-4875-a178-52ce5119a703
media_bytes=1073741824
layout_bytes=1073741824
usb_vendor=1234
usb_product=5678
usb_serial=fixture-stick
usb_route=1
usb_controller=392280000.usb
removable=1
IDENTITY
    for f in bin/busybox sbin/openrc sbin/openrc-run etc/init.d/mount-ro; do
        printf '%s\n' '#!/bin/sh' 'exit 0' >"$root/fixture-root/$f"
        chmod 755 "$root/fixture-root/$f"
    done
    ln -s /bin/busybox "$root/fixture-root/sbin/init"
    ln -s /etc/init.d/mount-ro "$root/fixture-root/etc/runlevels/shutdown/mount-ro"
    echo e4731abe-3566-4c3a-8019-c8828ca27a5a >"$root/fixture-root/etc/wallace-root-partuuid"
    echo 'keymap="no"' >"$root/fixture-root/etc/conf.d/keymaps"
    echo 'Option "XkbLayout" "no"' >"$root/fixture-root/etc/X11/xorg.conf.d/00-keyboard.conf"
    cp /in/keymap "$root/fixture-root/etc/wallace-no.bmap"
    echo usb-daily-6005-v1 >"$root/fixture-root/etc/wallace-root-profile"
    cp /work/fsck-stub "$root/fixture-root/etc/init.d/t6040-keymap"
    cp /work/fsck-stub "$root/fixture-root/usr/local/sbin/t6040-usb-root-openrc"
    ln -s /etc/init.d/t6040-keymap "$root/fixture-root/etc/runlevels/boot/t6040-keymap"
    printf '%s\n' '::sysinit:/sbin/openrc sysinit' '::wait:/sbin/openrc default' \
        '::shutdown:/usr/local/sbin/t6040-usb-root-openrc shutdown' >"$root/fixture-root/etc/inittab"
}

# All pre-RW failures must stop before ROOT_RW. Post-RW failures must clean up
# and never report a successful handoff. switch_root itself is an exec boundary.
cases='clean initial_mkdir initial_dev no_keymap bad_keymap load_keymap initial_proc initial_sys bad_cpu no_selector no_metadata no_fsck bad_cmdline wrong_serial no_stick duplicate mounted stale_extent metadata_first fsck inspect_mount bad_root_uuid missing_openrc bad_root_keymap missing_xorg missing_mountro bad_root_profile missing_root_map bad_root_map missing_root_keymap_service missing_root_keymap_link missing_shutdown_wrapper bad_shutdown_entry inspect_unmount metadata_second identity_second rw_mount handoff_mkdir handoff_dev handoff_proc handoff_sys'
: >/out/results.tsv
fail=0
for c in $cases; do
    root=/work/case-$c
    make_fixture "$root"
    echo "$c" >"$root/inject"
    case "$c" in
        no_keymap) rm "$root/etc/wallace-no.bmap" ;;
        bad_keymap) echo bad >"$root/etc/wallace-no.bmap" ;;
        bad_cpu) echo 0-1 >"$root/sys/devices/system/cpu/online" ;;
        no_selector) rm "$root/opt/wallace/t6040-usb-root-select.sh" ;;
        no_metadata) rm "$root/sbin/t6040-usb-root-metadata" ;;
        no_fsck) rm "$root/sbin/e2fsck" ;;
        bad_cmdline) echo 'root=/dev/nvme0n1p3' >"$root/proc/cmdline" ;;
        wrong_serial) echo wrong >"$root/sys/devices/platform/soc/392280000.usb/usb3/3-1/serial" ;;
        no_stick) rm "$root/sys/class/block/sda" "$root/sys/class/block/sda1" ;;
        duplicate) make_disk "$root" sdb 16 3-2 ;;
        mounted) echo '1 0 8:1 / /other rw - ext4 /dev/sda1 rw' >"$root/proc/self/mountinfo" ;;
        stale_extent) echo 4096 >"$root/sys/devices/platform/soc/392280000.usb/usb3/3-1/host0/block/sda/sda1/start" ;;
        bad_root_uuid) echo wrong >"$root/fixture-root/etc/wallace-root-partuuid" ;;
        missing_openrc) rm "$root/fixture-root/sbin/openrc" ;;
        bad_root_keymap) echo 'keymap="us"' >"$root/fixture-root/etc/conf.d/keymaps" ;;
        missing_xorg) rm "$root/fixture-root/etc/X11/xorg.conf.d/00-keyboard.conf" ;;
        missing_mountro) rm "$root/fixture-root/etc/runlevels/shutdown/mount-ro" ;;
        bad_root_profile) echo wrong >"$root/fixture-root/etc/wallace-root-profile" ;;
        missing_root_map) rm "$root/fixture-root/etc/wallace-no.bmap" ;;
        bad_root_map) echo wrong >"$root/fixture-root/etc/wallace-no.bmap" ;;
        missing_root_keymap_service) rm "$root/fixture-root/etc/init.d/t6040-keymap" ;;
        missing_root_keymap_link) rm "$root/fixture-root/etc/runlevels/boot/t6040-keymap" ;;
        missing_shutdown_wrapper) rm "$root/fixture-root/usr/local/sbin/t6040-usb-root-openrc" ;;
        bad_shutdown_entry) echo '::shutdown:/sbin/openrc shutdown' >"$root/fixture-root/etc/inittab" ;;
    esac
    rc=0
    timeout -s KILL 2 unshare --pid --fork --kill-child=KILL \
        chroot "$root" /real/bin/busybox sh /init >"/out/$c.console" 2>&1 || rc=$?
    cp "$root/trace" "/out/$c.trace"
    trace=/out/$c.trace
    reason= verdict=PASS
    if grep -q FORBIDDEN "$trace"; then reason='forbidden command'; fi
    if grep -q 'TERMINAL rescue keymap=no' "$trace"; then reason='shell before keymap'; fi
    case "$c" in
        clean)
            [ "$rc" -eq 0 ] || reason='clean case did not exit normally'
            grep -q '^TERMINAL switch-root$' "$trace" || reason='no handoff'
            [ "$(cat "$root/metadata-count")" = 2 ] || reason='wrong metadata count'
            grep -q '^FSCK -f -n /dev/sda1$' "$trace" || reason='missing read-only fsck'
            [ "$(cat "$root/root-state")" = rw ] || reason='not RW at handoff'
            ;;
        handoff_mkdir|handoff_dev|handoff_proc|handoff_sys)
            grep -q '^ROOT_RW$' "$trace" || reason='injection phase not reached'
            grep -q '^CLEANUP_RO$' "$trace" || reason='no cleanup remount'
            grep -q '^CLEANUP_UNMOUNT$' "$trace" || reason='no cleanup unmount'
            [ "$(cat "$root/root-state")" = absent ] || reason='root left mounted'
            ;;
        *)
            if grep -q '^ROOT_RW$' "$trace"; then reason='RW mount after rejected precondition'; fi
            ;;
    esac
    if [ "$c" != clean ]; then
        if grep -q '^TERMINAL switch-root$' "$trace"; then reason='handoff after failure'; fi
        grep -Eq '^TERMINAL (rescue|no-shell)' "$trace" || reason='no explicit stop'
    fi
    case "$c" in
        initial_mkdir|initial_dev|load_keymap|initial_proc|initial_sys|metadata_first|metadata_second|identity_second|fsck|inspect_mount|inspect_unmount|rw_mount|handoff_mkdir|handoff_dev|handoff_proc|handoff_sys)
            grep -q "^INJECT $c$" "$trace" || reason='injection did not fire' ;;
    esac
    if [ "$c" = metadata_first ] && [ "$(cat "$root/metadata-count")" != 1 ]; then reason='metadata failure was retried'; fi
    if [ -n "$reason" ]; then verdict=FAIL; fail=$((fail + 1)); fi
    printf '%s\t%s\t%s\t%s\n' "$c" "$verdict" "$rc" "$reason" >>/out/results.tsv
    rm -rf "$root"
done
cat /out/results.tsv
echo "startup control-flow failures=$fail"
[ "$fail" -eq 0 ]
