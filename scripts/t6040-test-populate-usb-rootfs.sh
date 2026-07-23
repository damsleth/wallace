#!/usr/bin/env bash
# Host-only tests for t6040-populate-usb-rootfs.sh. No block device is touched.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOL="$ROOT/scripts/t6040-populate-usb-rootfs.sh"
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
ALPINE=${ALPINE:-"$OUT/alpine-minirootfs-3.24.0-aarch64.tar.gz"}
PARTUUID=11111111-2222-3333-4444-555555555555

[ -f "$ALPINE" ] || {
    echo "missing pinned Alpine archive: $ALPINE" >&2
    exit 1
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/t6040-rootfs-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p \
    "$TMP/modules/7.1.3-t6040" \
    "$TMP/firmware/apple" \
    "$TMP/root"
printf 'fixture module\n' >"$TMP/modules/7.1.3-t6040/fixture.ko"
printf 'fixture firmware\n' >"$TMP/firmware/apple/fixture.bin"

"$TOOL" stage \
    --root "$TMP/root" \
    --partuuid "$PARTUUID" \
    --alpine "$ALPINE" \
    --modules "$TMP/modules" \
    --firmware "$TMP/firmware" \
    --manifest "$TMP/manifest.txt"

grep -Fx "PARTUUID=$PARTUUID / ext4 defaults,noatime 0 1" \
    "$TMP/root/etc/fstab"
grep -Fx "root_bootarg=root=PARTUUID=$PARTUUID rootfstype=ext4 rootwait" \
    "$TMP/manifest.txt"
grep -Fq 'lib/modules/7.1.3-t6040/fixture.ko' "$TMP/manifest.txt"
grep -Fq 'lib/firmware/apple/fixture.bin' "$TMP/manifest.txt"
[ -x "$TMP/root/bin/busybox" ]
[ -L "$TMP/root/sbin/init" ]
[ "$(readlink "$TMP/root/sbin/init")" = /bin/busybox ]

mkdir "$TMP/nonempty"
printf 'guard\n' >"$TMP/nonempty/user-data"
if "$TOOL" stage \
    --root "$TMP/nonempty" \
    --partuuid "$PARTUUID" \
    --alpine "$ALPINE" \
    --modules "$TMP/modules" \
    --firmware "$TMP/firmware" \
    --manifest "$TMP/should-not-exist.txt" >/dev/null 2>&1; then
    echo "non-empty stage root was not rejected" >&2
    exit 1
fi
grep -Fx guard "$TMP/nonempty/user-data"
[ ! -e "$TMP/should-not-exist.txt" ]

mkdir "$TMP/bad-hash-root"
if "$TOOL" stage \
    --root "$TMP/bad-hash-root" \
    --partuuid "$PARTUUID" \
    --alpine "$ALPINE" \
    --alpine-sha256 \
        0000000000000000000000000000000000000000000000000000000000000000 \
    --modules "$TMP/modules" \
    --firmware "$TMP/firmware" \
    --manifest "$TMP/bad-hash.txt" >/dev/null 2>&1; then
    echo "bad Alpine hash was not rejected" >&2
    exit 1
fi
[ -z "$(find "$TMP/bad-hash-root" -mindepth 1 -print -quit)" ]

if [ "$(uname -s)" != Linux ]; then
    if "$TOOL" device \
        --device /dev/null \
        --confirm ERASE:/dev/null \
        --alpine "$ALPINE" \
        --modules "$TMP/modules" \
        --firmware "$TMP/firmware" \
        --manifest "$TMP/device.txt" >/dev/null 2>&1; then
        echo "device mode was not rejected on a non-Linux host" >&2
        exit 1
    fi
fi

echo "USB rootfs host tests: PASS"
