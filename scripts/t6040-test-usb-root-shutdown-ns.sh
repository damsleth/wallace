#!/bin/sh
# SPDX-License-Identifier: MIT
# Container half; no physical target, only fresh scratch ext4/loop fixtures.
set -eu
apk add --no-cache e2fsprogs util-linux coreutils >/out/apk.log 2>&1
# Explicit seccomp policy must remain active despite the privileged container.
grep -Eq '^Seccomp:[[:space:]]+2$' /proc/self/status || { echo 'missing reboot-syscall block'; exit 1; }
mount -t devtmpfs none /dev
apk info -v > /out/container-packages.txt
mkdir -p /work/template /work/ird/bin /work/ird/lib
cp -a /candidate/. /work/template/
# The production root remains untouched. Only this fixture disables network
# services and gettys. OpenRC sysinit/boot and shutdown services are real.
rm -rf /work/template/etc/runlevels/default
mkdir /work/template/etc/runlevels/default
rm /work/template/etc/runlevels/boot/t6040-keymap
rm /work/template/etc/runlevels/boot/sysctl
# No VM-global sysctl/module/loglevel changes are needed for this filesystem
# test. UTS/IPC/network namespaces below contain the other normal boot effects.
: >/work/template/etc/modules
mkdir -p /work/template/real/bin /work/template/etc/harness
cp /work/template/bin/busybox /work/template/real/bin/busybox
ln -sf /real/bin/busybox /work/template/bin/sh
ln -sf /real/bin/busybox /work/template/sbin/init
cp /in/shutdown /work/template/usr/local/sbin/t6040-usb-root-openrc
cp /candidate/bin/busybox /work/ird/bin/busybox
cp -L /candidate/lib/ld-musl-aarch64.so.1 /work/ird/lib/ld-musl-aarch64.so.1
cat >/work/template/bin/busybox <<'SHIM'
#!/real/bin/busybox sh
R=/real/bin/busybox
base=${0##*/}
if [ "$base" = busybox ]; then app=$1; shift; else app=$base; fi
echo "BB $app $*" >&7
inj=$($R cat /etc/harness/inject)
case "$app" in
    halt) if [ "$*" = -w ]; then exec "$R" halt -w; fi
        echo 'FORBIDDEN power action' >&7; exit 99 ;;
    poweroff|reboot|halt) echo 'FORBIDDEN power action' >&7; exit 99 ;;
    sysctl|modprobe|dmesg) echo "HARNESS_SKIP $app $*" >&7; exit 0 ;;
    loadkmap) echo KEYMAP_LOAD >&7; exit 0 ;; # VM has no physical VT
    sh) if [ "$*" = -i ]; then echo 'TERMINAL rescue' >&7; exec "$R" sleep 3600; fi ;;
    mount)
        if [ "$*" = '-o remount,ro /' ] && [ "$inj" = remount_failure ]; then
            echo INJECT-remount >&7; exit 1
        fi ;;
    awk)
        if [ "$inj" = bad_mountinfo ]; then
            case "$*" in *'/proc/self/mountinfo') echo INJECT-mountinfo >&7; exit 1 ;; esac
        fi ;;
    sleep)
        if [ "$1" = 3600 ]; then echo 'TERMINAL no-return' >&7; fi ;;
esac
exec "$R" "$app" "$@"
SHIM
chmod 755 /work/template/bin/busybox
cat >/work/template/usr/local/sbin/harness-entry <<'ENTRY'
#!/real/bin/busybox sh
R=/real/bin/busybox
echo "PID=$$" >&7
[ "$$" -eq 1 ] || exit 99
echo "namespace=$($R readlink /proc/self/ns/pid)" >&7
echo 'rc_sys=""' >>/etc/rc.conf
# OpenRC sees the fresh /proc (this PID namespace), never the VM's processes.
/sbin/openrc sysinit
/sbin/openrc boot
/sbin/openrc default
echo runtime-data >/root/persistence-fixture
$R sync
echo OPENRC_READY >&7
inj=$($R cat /etc/harness/inject)
if [ "$inj" = openrc_failure ] || [ "$inj" = no_map_failure ]; then
    $R mv /sbin/openrc /sbin/openrc.real
    printf '#!/bin/sh\necho INJECT-openrc >&7\nexit 1\n' >/sbin/openrc
    $R chmod 755 /sbin/openrc
fi
[ "$inj" != no_map_failure ] || $R rm /etc/wallace-no.bmap
/usr/local/sbin/t6040-usb-root-openrc shutdown
rc=$?
echo "SHUTDOWN_RETURN $rc" >&7
$R awk '$5=="/" {print "FINAL_ROOT "$0}' /proc/self/mountinfo >&7
echo TERMINAL-success >&7
exit "$rc"
ENTRY
chmod 755 /work/template/usr/local/sbin/harness-entry
cat >/work/ird/init <<'BOOT'
#!/bin/busybox sh
BB=/bin/busybox
$BB mount --make-rprivate /
$BB mkdir -p /newroot /dev
$BB mount -t devtmpfs none /dev || exit 99
$BB mount -t ext4 -o rw "$1" /newroot || exit 99
for x in dev proc sys; do $BB mkdir -p /newroot/$x; done
$BB mount -t devtmpfs none /newroot/dev || exit 99
$BB mount -t proc none /newroot/proc || exit 99
$BB mount -t sysfs none /newroot/sys || exit 99
exec $BB switch_root /newroot /bin/sh /usr/local/sbin/harness-entry
BOOT
chmod 755 /work/ird/init
truncate -s 192M /work/template.ext4
mkfs.ext4 -q -F -L test-only -d /work/template /work/template.ext4
sha256sum /in/test.sh /in/shutdown /candidate/bin/busybox /candidate/etc/init.d/mount-ro \
    /candidate/sbin/openrc > /out/source-hashes.txt
: >/out/results.tsv
failed=0
for c in clean no_mountro_link openrc_failure remount_failure bad_mountinfo no_map_failure; do
    cp --sparse=always /work/template.ext4 /work/$c.ext4
    loop=$(losetup -f --show /work/$c.ext4)
    mkdir -p /work/config
    mount -t ext4 "$loop" /work/config
    echo "$c" >/work/config/etc/harness/inject
    if [ "$c" = no_mountro_link ]; then rm /work/config/etc/runlevels/shutdown/mount-ro; fi
    umount /work/config
    mkdir -p /work/boot-$c
    cp -a /work/ird/. /work/boot-$c/
    # switch_root requires the initial root to be a mountpoint; use a private
    # tmpfs, not the container root or any host directory.
    cat >/work/run-$c.sh <<RUN
#!/bin/sh
mount --make-rprivate /
mount -t tmpfs none /work/boot-$c
cp -a /work/ird/. /work/boot-$c/
exec chroot /work/boot-$c /bin/busybox sh /init $loop
RUN
    rc=0
    timeout -s KILL 15 unshare --mount --pid --uts --ipc --net --fork --kill-child=KILL \
        sh /work/run-$c.sh 7>"/out/$c.trace" >"/out/$c.console" 2>&1 || rc=$?
    # Namespace exit discards mounts. Only now detach the known fixture loop.
    losetup -d "$loop"
    # Namespace teardown/loop autoclear is asynchronous after timeout kills PID1.
    n=0
    while losetup "$loop" >/dev/null 2>&1 && [ "$n" -lt 50 ]; do
        sleep 0.1
        n=$((n + 1))
    done
    if losetup "$loop" >/dev/null 2>&1; then
        echo "fixture loop still active after namespace exit: $loop" >&2
        exit 1
    fi
    fsck=0
    e2fsck -f -n /work/$c.ext4 >"/out/$c.fsck" 2>&1 || fsck=$?
    verdict=PASS; reason=
    tr=/out/$c.trace
    grep -q '^PID=1$' "$tr" || reason='not PID1'
    grep -q '^OPENRC_READY$' "$tr" || reason='OpenRC startup did not finish'
    if grep -q FORBIDDEN "$tr"; then reason='power action attempted'; fi
    case "$c" in
        clean|no_mountro_link)
            grep -q '^TERMINAL-success$' "$tr" || reason='no clean return'
            grep -q '^FINAL_ROOT .* / ro,' "$tr" || reason='root not RO at return'
            [ "$rc" = 0 ] || reason="exit=$rc"
            [ "$fsck" = 0 ] || reason="fsck=$fsck" ;;
        *)
            if grep -q '^TERMINAL-success$' "$tr"; then reason='returned after failure'; fi
            grep -Eq '^TERMINAL (rescue|no-return)$' "$tr" || reason='no deliberate stop'
            case "$c" in
                openrc_failure|no_map_failure) grep -q INJECT-openrc "$tr" || reason='injection did not fire' ;;
                remount_failure) grep -q INJECT-remount "$tr" || reason='injection did not fire' ;;
                bad_mountinfo) grep -q INJECT-mountinfo "$tr" || reason='injection did not fire' ;;
            esac
            if [ "$c" = no_map_failure ] && grep -q '^TERMINAL rescue$' "$tr"; then reason='shell without keymap'; fi
            ;;
    esac
    if [ -n "$reason" ]; then verdict=FAIL; failed=$((failed + 1)); fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$c" "$verdict" "$rc" "$fsck" "$reason" | tee -a /out/results.tsv
    rm -rf /work/boot-$c /work/$c.ext4
done
echo "shutdown failures=$failed"
[ "$failed" = 0 ]
