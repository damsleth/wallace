#!/usr/bin/env bash
# Host-only regression test for the SD-root clean-shutdown path (ticket 3006).
#
# Runs the real /init shutdown-tmpfs block, inittab, OpenRC wrapper, powerctl
# and shutdown program against real tmpfs/exFAT/ext4/loop mounts in a throwaway
# PID+mount namespace inside a privileged podman container. OpenRC 0.63.2's
# sysinit mounts and mount-ro service are replayed; one failure is injected per
# phase. No T6040, SD card, rig lease or host disk is involved.
#
# usage: t6040-test-sdroot-shutdown.sh [--rev GIT-REV] [--out DIR]
#                                      [--injection-topology bare|openrc]
#   --rev    test the scripts as committed at GIT-REV (default: working tree)
#   --out    results directory (default: a fresh scratch directory)
#
# Exit status 0 only if every case meets the contract:
#   * a clean request ends in the requested poweroff/reboot with no ext4 or
#     exFAT mount left, the root loop detached, and both filesystems passing
#     read-only fsck;
#   * an injected failure always fires and always ends in the rescue shell,
#     never in poweroff/reboot.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTBASE=${OUT:-$HOME/Code/linux-build-out}
INITRAMFS=${SDROOT_INITRAMFS:-$OUTBASE/initramfs-sdroot-daily-v2.build1.cpio.gz}
# The card root is Alpine 3.24 (OpenRC 0.63.2). Its BusyBox init must be the
# one under test: Alpine 3.22's 1.37.0-r20 silently drops every ::restart entry
# (aports c792a061 fixed the truncated action_type in 3.23+).
CARD_ROOTFS=${CARD_ROOTFS:-$OUTBASE/alpine-minirootfs-3.24.0-aarch64.tar.gz}
CARD_ROOTFS_SHA256=4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a
# alpine:3.22, pinned by digest. Loop devices and devtmpfs need real root, so the
# container runs under the podman VM's rootful podman (the machine is rootless).
IMAGE=${IMAGE:-docker.io/library/alpine@sha256:2c9d26f410d032d5b1525aa8a873e238b05b90c4ae8618743d4311f0cc827e37}
PODMAN=${PODMAN:-podman machine ssh -- sudo podman}
REV="" RES="" INJ_TOPO=openrc

while [ $# -gt 0 ]; do
    case "$1" in
        --rev) REV=$2; shift 2 ;;
        --out) RES=$2; shift 2 ;;
        --injection-topology) INJ_TOPO=$2; shift 2 ;;
        *) echo "usage: $0 [--rev GIT-REV] [--out DIR] [--injection-topology bare|openrc]" >&2; exit 2 ;;
    esac
done
case "$INJ_TOPO" in bare|openrc) ;; *) echo "bad --injection-topology" >&2; exit 2 ;; esac

# podman on macOS shares only $HOME with its VM, so stage under the build output.
STAGE=$(mktemp -d "$OUTBASE/t6040-3006.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
RES=${RES:-$STAGE/out}
mkdir -p "$RES" "$STAGE/in/variant"

fetch() {  # fetch <repo path> <dest>
    if [ -n "$REV" ]; then git -C "$ROOT" show "$REV:$1" >"$2"; else cp "$ROOT/$1" "$2"; fi
}
for f in init shutdown powerctl inittab openrc early-console; do
    fetch "scripts/t6040-sdroot-$f" "$STAGE/in/variant/$f"
done
chmod 0755 "$STAGE/in/variant/"*

[ -f "$INITRAMFS" ] || { echo "missing $INITRAMFS (set SDROOT_INITRAMFS)" >&2; exit 1; }
gzip -dc "$INITRAMFS" | (cd "$STAGE/in" && bsdtar -xf - bin/busybox)
mv "$STAGE/in/bin/busybox" "$STAGE/in/busybox"
cp "$ROOT/scripts/t6040-test-sdroot-shutdown-ns.sh" "$STAGE/in/ns.sh"
echo "$CARD_ROOTFS_SHA256  $CARD_ROOTFS" | shasum -a 256 -c - >/dev/null
mkdir -p "$STAGE/in/card"
tar -xzf "$CARD_ROOTFS" -C "$STAGE/in/card" ./bin/busybox ./lib/ld-musl-aarch64.so.1 \
    ./lib/libc.musl-aarch64.so.1

{
    echo "rev=${REV:-working-tree}"
    echo "git_head=$(git -C "$ROOT" rev-parse HEAD)"
    echo "initramfs=$(basename "$INITRAMFS") $(shasum -a 256 "$INITRAMFS" | cut -d' ' -f1)"
    echo "card_rootfs=$(basename "$CARD_ROOTFS") $CARD_ROOTFS_SHA256"
    echo "image=$IMAGE"
    echo "injection_topology=$INJ_TOPO"
    (cd "$STAGE/in" && shasum -a 256 busybox card/bin/busybox ns.sh variant/*)
} >"$RES/manifest.txt"

# name, topology, trigger, action, injected "pattern(+ for space) rc" or -
{
    printf '%s\t%s\t%s\t%s\t%s\n' \
        clean-bare-poweroff     bare           powerctl poweroff - \
        clean-bare-reboot       bare           powerctl reboot   - \
        clean-openrc-poweroff   openrc         powerctl poweroff - \
        clean-openrc-reboot     openrc         powerctl reboot   - \
        clean-mountro-poweroff  openrc+mountro powerctl poweroff - \
        clean-mountro-reboot    openrc+mountro powerctl reboot   - \
        clean-mountro-sigquit   openrc+mountro sigquit  reboot   - \
        bad-action              openrc         sigquit  bogus    -
    i=0
    for pat in 'umount+/mnt/sd 1' 'pivot_root+.+oldroot 1' 'mount+-t+proc* 1' \
               'mount+-t+devtmpfs* 1' 'umount+/oldroot/dev/shm 1' 'umount+/oldroot/dev 1' \
               'umount+/oldroot/proc 1' 'umount+/oldroot/sys 1' 'umount+/oldroot/run 1' \
               'mount+-o+remount,ro+/oldroot 1' 'umount+/oldroot 1' 'losetup+-d* 1' \
               'umount+/sd 1' 'grep+-Eq*/proc/mounts 0' 'losetup+/dev/loop* 0'; do
        i=$((i + 1))
        printf 'inject-%02d\t%s\tpowerctl\tpoweroff\t%s\n' "$i" "$INJ_TOPO" "$pat"
    done
} >"$STAGE/in/cases.tsv"
cp "$STAGE/in/cases.tsv" "$RES/cases.tsv"

podman machine ssh 'sudo modprobe exfat' >/dev/null 2>&1 || true
$PODMAN run --rm --privileged -v "$STAGE/in:/in:ro" -v "$RES:/out" \
    --tmpfs /work:rw,exec,size=1g "$IMAGE" sh /in/ns.sh
podman machine ssh 'sudo rm -f /dev/ttydc0' >/dev/null 2>&1 || true

# Verdicts.
fail=0
: >"$RES/verdicts.tsv"
while IFS=$'\t' read -r name topo trigger action inject; do
    row=$(awk -F'\t' -v n="$name" '$1==n' "$RES/results.tsv")
    IFS=$'\t' read -r _ terminal trig_rc mounts loop fsck <<<"$row"
    tr="$RES/$name.trace"
    why=""
    if [ -z "$row" ]; then
        why="no result"
    elif [ "$inject" = - ] && [ "$action" != bogus ]; then
        [ "$terminal" = "$action" ] || why="terminal=$terminal, want $action"
        [ "$mounts" = 0/0 ] || why="$why${why:+; }ext4/exfat mounts left: $mounts"
        [ "$loop" = no ] || why="$why${why:+; }root loop still attached"
        case "$fsck" in clean*) ;; *) why="$why${why:+; }fsck=$fsck" ;; esac
    else
        if [ "$inject" != - ] && ! grep -q '^INJECT' "$tr"; then
            why="injection did not fire"
        fi
        [ "$terminal" = rescue-shell ] || why="$why${why:+; }terminal=$terminal, want rescue-shell"
    fi
    if grep -Eq '^TERMINAL (poweroff|reboot|halt)' "$tr" && [ "$mounts" != 0/0 ]; then
        why="$why${why:+; }POWER ACTION WITH FILESYSTEMS MOUNTED"
    fi
    if [ -z "$why" ]; then v=PASS; else v=FAIL; fail=1; fi
    printf '%s\t%s\t%s\t%s\n' "$v" "$name" "$terminal" "${why:--}" | tee -a "$RES/verdicts.tsv"
done <"$STAGE/in/cases.tsv"

echo "results: $RES"
exit "$fail"
