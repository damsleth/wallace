#!/bin/sh
# Container half of t6040-test-sdroot-shutdown.sh (ticket 3006). Do not run
# directly: it expects a privileged Alpine container prepared by the driver.
#
# One case = a fresh exFAT "SD64" image on a loop device, holding a fresh ext4
# wallace-root.img. A new PID+mount namespace replays the SD-root /init mount
# topology (the shutdown-tmpfs block is copied verbatim from the variant's
# init), switch_roots into the ext4 root and runs the card's real BusyBox init
# with the variant's real inittab, OpenRC wrapper and powerctl. /sbin/openrc is
# a stub that replays OpenRC 0.63.2's sysinit mounts and, optionally, its
# mount-ro shutdown service. The variant's real shutdown program runs unmodified
# as PID 1; only its $BB is interposed by a shim that logs every applet, injects
# one failure on request, and never forwards poweroff/reboot/halt.
#
# Nothing here touches the T6040, an SD card, or any host disk: every block
# device is a loop over a file in the container's scratch directory.
set -eu

IN=/in
OUT=/out
CASES=$IN/cases.tsv
WORK=/work
CARD=$IN/card                   # Alpine 3.24.0 minirootfs bin/ and lib/: the card's PID 1
IRD_BB=$IN/busybox              # BusyBox from the reviewed SD-root initramfs
UUID=4c41b99c-7747-4688-85a5-397bc5d784a2

apk add -q e2fsprogs exfatprogs util-linux coreutils >/dev/null
# podman's /dev is a static copy; loop nodes appear only in the VM's devtmpfs.
mount -t devtmpfs none /dev
apk info -v 2>/dev/null | grep -E '^(busybox|coreutils|e2fsprogs|exfatprogs|util-linux)-[0-9]' \
    >"$OUT/container-packages.txt"
grep -qw exfat /proc/filesystems || { echo "exfat is not available in the VM kernel" >&2; exit 1; }
[ -x "$IRD_BB" ] || { echo "missing initramfs busybox" >&2; exit 1; }

log() { echo "harness: $*"; }

# --- the shim installed as the shutdown tmpfs's bin/busybox -------------------
# Its interpreter path resolves before the pivot (the tmpfs is /run/initramfs)
# and after it (tmpfs:/run/initramfs is a symlink to /).
cat >"$WORK/shim" <<'EOF'
#!/run/initramfs/bin/busybox.real sh
R=/run/initramfs/bin/busybox.real
H=/run/initramfs/h
echo "bb: $*" >&7
case "$*" in
    poweroff*|reboot*|halt*)
        echo "TERMINAL ${1}" >&7
        exec "$R" sleep 3600 ;;
    "sh -i")
        echo "TERMINAL rescue-shell" >&7
        exec "$R" sleep 3600 ;;
    "sh "*)
        exec "$R" "$@" ;;
esac
if [ -r "$H/fail" ]; then
    read -r pat rc <"$H/fail"
    pat=$(echo "$pat" | "$R" tr '+' ' ')
    # shellcheck disable=SC2254
    case "$*" in
        $pat) echo "INJECT rc=$rc: $*" >&7; exit "$rc" ;;
    esac
fi
"$R" "$@"
rc=$?
echo "  rc=$rc" >&7
exit "$rc"
EOF

# --- /sbin/openrc stub on the card root ---------------------------------------
cat >"$WORK/openrc-stub" <<'EOF'
#!/bin/busybox sh
# Replays the mount side effects of OpenRC 0.63.2 (openrc-0.63.2-r0.apk):
#   usr/libexec/rc/sh/init.sh:72-83  tmpfs on /run unless /run is a mountpoint
#   etc/init.d/devfs:93-111          mqueue, devpts, shm
#   etc/init.d/sysfs:40-125          securityfs, debugfs, configfs, pstore, bpf
#   etc/init.d/mount-ro              shutdown: umount -r everything not skipped
# The set matches the 2026-08-19 SD-root transcript (dcuart-console.log:2084-2115).
BB=/bin/busybox
T=$($BB cat /etc/harness/topology)
log() { echo "openrc-stub[$1/$T]: $2" >&7; }
ismnt() { $BB awk -v m="$1" '$2==m{f=1} END{exit !f}' /proc/mounts; }
hasfs() { $BB grep -Eq "[[:space:]]$1\$" /proc/filesystems; }
act=${1:-}
case "$act" in
sysinit)
    [ "$T" = bare ] && { log sysinit "no OpenRC mounts"; exit 0; }
    if ismnt /run; then
        log sysinit "/run is already a mountpoint; not mounting"
    else
        $BB mount -t tmpfs -o mode=0755,nosuid,nodev,nr_inodes=800k,size=20%,strictatime tmpfs /run &&
            log sysinit "mounted tmpfs on /run"
    fi
    $BB mkdir -p /run/openrc /run/lock
    for x in "mqueue /dev/mqueue 1777 ,nodev mqueue" \
             "devpts /dev/pts 0755 ,gid=5,mode=0620 devpts" \
             "tmpfs /dev/shm 1777 ,nodev,mode=1777 shm"; do
        set -- $x
        hasfs "$1" || continue
        ismnt "$2" && continue
        $BB mkdir -m "$3" -p "$2"
        $BB mount -n -t "$1" -o "noexec,nosuid$4" "$5" "$2" && log sysinit "mounted $2"
    done
    o=nodev,noexec,nosuid
    for x in "securityfs /sys/kernel/security" "debugfs /sys/kernel/debug" \
             "configfs /sys/kernel/config" "pstore /sys/fs/pstore" "bpf /sys/fs/bpf"; do
        set -- $x
        [ -d "$2" ] && ! ismnt "$2" && hasfs "$1" || continue
        $BB mount -n -t "$1" -o "$o" "$1" "$2" && log sysinit "mounted $2"
    done
    ;;
default)
    log default "READY"
    ;;
shutdown)
    [ "$T" = openrc+mountro ] || { log shutdown "no mount-ro in the shutdown runlevel"; exit 0; }
    $BB sync
    m='^(/dev|/dev/.*|/proc|/proc.*|/sys|/sys/.*|/run|/run/openrc|/bin|/sbin|/lib(32|64)?|/libexec)$'
    # mountinfo lists newest first; do_unmount re-checks each point is mounted.
    for mnt in $($BB awk '{print $2}' /proc/mounts | $BB tac); do
        echo "$mnt" | $BB grep -Eq "$m" && continue
        ismnt "$mnt" || continue
        if $BB umount -r "$mnt" 2>/dev/null; then
            log shutdown "umount -r $mnt: ok ($(ismnt "$mnt" && echo remounted-ro || echo unmounted))"
        else
            log shutdown "umount -r $mnt: failed"
        fi
    done
    ;;
*)
    log "$act" "ignored"
    ;;
esac
exit 0
EOF

# --- one case ------------------------------------------------------------------
run_case() {
    name=$1 topo=$2 trigger=$3 action=$4 inject=$5
    d=$WORK/$name
    rm -rf "$d"; mkdir -p "$d/ird" "$d/fix"
    tr=$OUT/$name.trace
    : >"$tr"

    # Fixture: exFAT SD64 on a loop device, ext4 wallace-root.img inside it.
    truncate -s 96M "$d/sd.img"
    mkfs.exfat -L SD64 "$d/sd.img" >/dev/null
    SDLOOP=$(losetup -f --show "$d/sd.img")
    mount -t exfat "$SDLOOP" "$d/fix"
    truncate -s 40M "$d/fix/wallace-root.img"
    mkfs.ext4 -q -F -U "$UUID" "$d/fix/wallace-root.img"
    mkdir -p "$d/root"
    mount -o loop "$d/fix/wallace-root.img" "$d/root"
    r=$d/root
    mkdir -p "$r/bin" "$r/sbin" "$r/lib" "$r/etc/harness" "$r/usr/local/sbin" \
        "$r/dev" "$r/proc" "$r/sys" "$r/run" "$r/mnt/sd" "$r/tmp" "$r/root"
    cp "$CARD/bin/busybox" "$r/bin/busybox"
    cp -a "$CARD"/lib/ld-musl-*.so.1 "$CARD"/lib/libc.musl-*.so.1 "$r/lib/"
    ln -s busybox "$r/bin/sh"
    ln -s /bin/busybox "$r/sbin/init"
    install -m 0644 "$IN/variant/inittab" "$r/etc/inittab"
    install -m 0755 "$IN/variant/early-console" "$r/usr/local/sbin/t6040-sdroot-early-console"
    install -m 0755 "$IN/variant/openrc" "$r/usr/local/sbin/t6040-sdroot-openrc"
    install -m 0755 "$IN/variant/powerctl" "$r/usr/local/sbin/t6040-sdroot-powerctl"
    ln -s t6040-sdroot-powerctl "$r/usr/local/sbin/poweroff"
    ln -s t6040-sdroot-powerctl "$r/usr/local/sbin/reboot"
    for s in t6040-sdroot-net t6040-startx t6040-net-up; do
        printf '#!/bin/sh\nexit 0\n' >"$r/usr/local/sbin/$s"; chmod 0755 "$r/usr/local/sbin/$s"
    done
    install -m 0755 "$WORK/openrc-stub" "$r/sbin/openrc"
    echo "$topo" >"$r/etc/harness/topology"
    umount "$r"
    umount "$d/fix"

    # The /init replica: the variant's shutdown-tmpfs block, verbatim.
    blk=$(awk '/^# Preserve only the shutdown tools/{p=1} /switch_root \/newroot/{p=0} p' "$IN/variant/init")
    echo "$blk" | grep -q 'mount -t tmpfs' || { echo "cannot extract the init shutdown block" >&2; exit 1; }
    {
        echo '#!/bin/busybox sh'
        echo 'BB=/bin/busybox'
        echo "PART=$SDLOOP"
        echo 'LOOP=""'
        echo 'say() { echo "replica: $*" >&7; }'
        echo 'stop() { echo "REPLICA-STOP: $*" >&7; exec "$BB" sleep 3600; }'
        echo 'cleanup_root() { :; }'
        echo '"$BB" mount -t proc none /proc && "$BB" mount -t sysfs none /sys && "$BB" mount -t devtmpfs none /dev || stop core'
        echo '"$BB" mkdir -p /sd /newroot'
        echo '"$BB" mount -t exfat -o rw "$PART" /sd || stop exfat'
        echo 'IMG=/sd/wallace-root.img'
        echo 'LOOP=$("$BB" losetup -f)'
        echo '"$BB" losetup "$LOOP" "$IMG" || stop losetup'
        echo 'echo "ROOTLOOP $LOOP" >&7'
        echo '"$BB" mount -t ext4 -o rw "$LOOP" /newroot || stop ext4'
        echo '# The VM has no DockChannel UART; the block requires the node to exist.'
        echo '[ -e /dev/ttydc0 ] || "$BB" ln -s null /dev/ttydc0'
        echo "$blk"
        echo '# --- harness interposition (not part of /init) ---'
        echo 'T=/newroot/run/initramfs'
        echo '"$BB" mv "$T/bin/busybox" "$T/bin/busybox.real" || stop interpose'
        echo '"$BB" cp /harness/shim "$T/bin/busybox" && "$BB" chmod 0755 "$T/bin/busybox" || stop interpose'
        echo '"$BB" mkdir -p "$T/run" "$T/h" && "$BB" ln -s / "$T/run/initramfs" || stop interpose'
        echo '[ ! -f /harness/fail ] || "$BB" cp /harness/fail "$T/h/fail"'
        echo 'echo "REPLICA switch_root" >&7'
        echo 'exec "$BB" switch_root /newroot /sbin/init'
    } >"$d/init-replica"
    [ "$inject" = - ] || echo "$inject" >"$d/fail"

    # Stage 0: becomes PID 1 of a new PID+mount namespace, makes a tmpfs the
    # root (BusyBox switch_root requires a ramfs/tmpfs root), and runs the replica.
    cat >"$d/stage0" <<EOF
set -e
mount -t tmpfs -o mode=0755 ird $d/ird
mkdir -p $d/ird/bin $d/ird/dev $d/ird/proc $d/ird/sys $d/ird/harness
cp $IRD_BB $d/ird/bin/busybox
install -m 0755 $d/init-replica $d/ird/init
install -m 0755 $IN/variant/shutdown $d/ird/shutdown
cp $WORK/shim $d/ird/harness/shim
[ ! -f $d/fail ] || cp $d/fail $d/ird/harness/fail
cd $d/ird
mount --move . /
exec /bin/busybox chroot . /init
EOF
    exec 7>>"$tr"
    # A non-interactive shell starts '&' jobs with SIGINT/SIGQUIT ignored, and
    # BusyBox init never resets them; the kernel starts a real init with every
    # signal at SIG_DFL, so restore that before the namespace init is created.
    env --default-signal unshare --mount --pid --fork --propagation private sh "$d/stage0" \
        >"$OUT/$name.console.raw" 2>&1 &
    upid=$!
    exec 7>&-
    ns=""
    i=0
    while [ -z "$ns" ] && [ $i -lt 50 ]; do ns=$(pgrep -P "$upid" || true); sleep 0.1; i=$((i+1)); done
    [ -n "$ns" ] || { echo "namespace init did not start" >&2; exit 1; }

    i=0
    until grep -q 'READY' "$tr" || [ $i -ge 150 ] || ! kill -0 "$ns" 2>/dev/null; do sleep 0.2; i=$((i+1)); done
    if ! grep -q READY "$tr"; then
        result "$name" "setup-failed" "-" "-" "-" "-"
        kill -KILL "$ns" 2>/dev/null || true; wait "$upid" 2>/dev/null || true
        cleanup_loops "$d" "$SDLOOP"
        return 0
    fi
    sleep 1
    cp "/proc/$ns/mountinfo" "$OUT/$name.mounts-before"
    sed -n 's/^ROOTLOOP //p' "$tr" | head -1 >"$d/ird-rootloop"

    trig_rc=-
    case "$trigger" in
        powerctl)
            set +e
            nsenter -t "$ns" -m -p -r -w "/usr/local/sbin/$action" >"$OUT/$name.trigger" 2>&1 &
            tpid=$!
            set -e ;;
        sigquit)
            [ "$action" = reboot ] || nsenter -t "$ns" -m -r -w /bin/busybox sh -c \
                "echo $action >/run/initramfs/action" >"$OUT/$name.trigger" 2>&1 || true
            kill -QUIT "$ns"; tpid="" ;;
    esac

    i=0
    until grep -q '^TERMINAL' "$tr" || [ $i -ge 200 ] || ! kill -0 "$ns" 2>/dev/null; do
        sleep 0.2; i=$((i+1))
        # powerctl refusing leaves the namespace idle: stop waiting once it exits.
        if [ -n "${tpid:-}" ] && ! kill -0 "$tpid" 2>/dev/null; then
            wait "$tpid" 2>/dev/null && trig_rc=0 || trig_rc=$?
            tpid=""
            grep -q '^TERMINAL' "$tr" || { sleep 3; grep -q '^TERMINAL' "$tr" || break; }
        fi
    done
    if [ -n "${tpid:-}" ]; then wait "$tpid" 2>/dev/null && trig_rc=0 || trig_rc=$?; fi

    terminal=$(sed -n 's/^TERMINAL //p' "$tr" | head -1)
    if [ -z "$terminal" ]; then
        if kill -0 "$ns" 2>/dev/null; then terminal=refused; else terminal=init-halted; fi
    fi
    ext4=- exfat=- loopattached=-
    if kill -0 "$ns" 2>/dev/null; then
        cp "/proc/$ns/mountinfo" "$OUT/$name.mounts-after"
        ext4=$(awk '/ - ext4 /{n++} END{print n+0}' "$OUT/$name.mounts-after")
        exfat=$(awk '/ - exfat /{n++} END{print n+0}' "$OUT/$name.mounts-after")
    fi
    # The exact device the replica attached (its backing path is only
    # meaningful inside the namespace, so match by device, not by path).
    rl=$(cat "$d/ird-rootloop" 2>/dev/null || true)
    if [ -n "$rl" ] && [ -e "/sys/block/${rl#/dev/}/loop/backing_file" ]; then
        loopattached=yes
    else
        loopattached=no
    fi

    # Check-only postcondition, only for a clean terminal state.
    fsck=-
    if [ "$ext4" = 0 ] && [ "$exfat" = 0 ] && [ "$loopattached" = no ]; then
        fl=$(dd if="$SDLOOP" bs=1 skip=106 count=2 2>/dev/null | od -An -tu2 | tr -d ' ')
        mkdir -p "$d/chk"
        if fsck.exfat -n "$SDLOOP" >"$OUT/$name.fsck" 2>&1 &&
           mount -t exfat -o ro "$SDLOOP" "$d/chk" &&
           e2fsck -fn "$d/chk/wallace-root.img" >>"$OUT/$name.fsck" 2>&1; then
            fsck="clean(exfat-flags=$fl)"
        else
            fsck="DIRTY(exfat-flags=$fl)"
        fi
        umount "$d/chk" 2>/dev/null || true
    fi
    result "$name" "$terminal" "$trig_rc" "$ext4/$exfat" "$loopattached" "$fsck"

    kill -KILL "$ns" 2>/dev/null || true
    wait "$upid" 2>/dev/null || true
    cleanup_loops "$d" "$SDLOOP"
}

cleanup_loops() {
    rl=$(cat "$1/ird-rootloop" 2>/dev/null || true)
    echo "$rl $2" >>"$WORK/attached-loops"
    [ -z "$rl" ] || losetup -d "$rl" 2>/dev/null || true
    losetup -d "$2" 2>/dev/null || true
}

result() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$OUT/results.tsv"
    log "$1: terminal=$2 trigger_rc=$3 ext4/exfat=$4 rootloop=$5 fsck=$6"
}

: >"$OUT/results.tsv"
while IFS='	' read -r name topo trigger action inject; do
    case "$name" in ''|'#'*) continue ;; esac
    run_case "$name" "$topo" "$trigger" "$action" "$inject"
    # Collapse BusyBox init's respawn noise for the absent DockChannel UART.
    uniq -c "$OUT/$name.console.raw" >"$OUT/$name.console"; rm -f "$OUT/$name.console.raw"
done <"$CASES"
rm -f /dev/ttydc0 2>/dev/null || true
# A killed namespace releases its mounts asynchronously, so a loop detached
# right after the kill may still be busy. Sweep exactly the devices we used.
for try in 1 2 3 4 5; do
    left=""
    for l in $(cat "$WORK/attached-loops" 2>/dev/null); do
        [ -e "/sys/block/${l#/dev/}/loop/backing_file" ] || continue
        losetup -d "$l" 2>/dev/null || true
        [ -e "/sys/block/${l#/dev/}/loop/backing_file" ] && left="$left $l"
    done
    [ -z "$left" ] && break
    sleep 2
done
[ -z "$left" ] || log "WARNING: loop devices still attached:$left"
