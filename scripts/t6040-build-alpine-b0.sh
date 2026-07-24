#!/usr/bin/env bash
# Build the pinned, reproducible OpenRC Alpine B0 RAM distro for T6040/J614s.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
CONTAINER=${CONTAINER:-kbuild}
ALPINE_VERSION=3.24.0
ALPINE_ARCH=aarch64
ALPINE_SHA256=4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a
ALPINE_FILE="alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/${ALPINE_ARCH}/${ALPINE_FILE}"
REPO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.24/main/${ALPINE_ARCH}"
ARCHIVE="$OUT/$ALPINE_FILE"
APK_DIR="$OUT/alpine-b0-apks-${ALPINE_VERSION}-${ALPINE_ARCH}"
DEST=${DEST:-"$OUT/initramfs-alpine-b0.cpio.gz"}

case "$DEST" in
    "$OUT"/*) ;;
    *) echo "DEST must be directly under $OUT" >&2; exit 1 ;;
esac

mkdir -p "$OUT" "$APK_DIR"
if [ ! -f "$ARCHIVE" ]; then
    curl -fL --retry 3 --output "$ARCHIVE.part" "$ALPINE_URL"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
printf '%s  %s\n' "$ALPINE_SHA256" "$ARCHIVE" | shasum -a 256 -c -

# Every package not already in the immutable minirootfs is named, versioned,
# and content-pinned. APK signatures are still verified during installation.
while read -r package_sha package_file; do
    [ -n "$package_sha" ] || continue
    package_path="$APK_DIR/$package_file"
    if [ ! -f "$package_path" ]; then
        curl -fL --retry 3 --output "$package_path.part" \
            "$REPO_URL/$package_file"
        mv "$package_path.part" "$package_path"
    fi
    printf '%s  %s\n' "$package_sha" "$package_path" | shasum -a 256 -c -
done <<'EOF'
fa0aeacfdac615e8f5f782f7c638fed248fcecc8dd5e1125d6d26c4697c5f798 bridge-1.5-r5.apk
7b97836546a587b85126aacec7d9a72496431b2f53e8dd1ec1c383d88a042a55 ifupdown-ng-0.13.0-r0.apk
e13be383f18b1fcfe895361d816ff7cfd2b3c265e442bb371c4a234b29b0e4a9 libcap2-2.78-r0.apk
625cd378f8e26a0a559986c9647375ea77a6e6d72025b6959d60d4bf0f1a572e openrc-0.63.2-r0.apk
2a219fe5b00e3b8e7e6c69b545839f46cdaad556a9948d2df8a1c953449e3070 openrc-user-0.63.2-r0.apk
EOF

TMP=$(mktemp -d "$OUT/alpine-b0.XXXXXX")
TMP_BASE=$(basename "$TMP")
DEST_BASE=$(basename "$DEST")
DEST_TMP=$(mktemp "$OUT/.${DEST_BASE}.XXXXXX")
case "$DEST_BASE" in
    *.cpio.gz) STEM=${DEST_BASE%.cpio.gz} ;;
    *) STEM=$DEST_BASE ;;
esac
CONTENTS="$OUT/$STEM.contents"
PACKAGES="$OUT/$STEM.packages"
SIZES="$OUT/$STEM.sizes"
MANIFEST="$OUT/$STEM.manifest"
trap '
    podman exec "$CONTAINER" rm -rf "/out/$TMP_BASE" >/dev/null 2>&1 || true
    rm -f "$DEST_TMP"
' EXIT

LC_ALL=C bsdtar -xf "$ARCHIVE" -C "$TMP"
install -d "$TMP/tmp/apks" "$TMP/usr/local/sbin" "$TMP/etc/init.d"
cp "$APK_DIR"/*.apk "$TMP/tmp/apks/"
: >"$TMP/etc/apk/repositories"

# The container and target are both aarch64. Install only local, hash-checked
# APKs; no repository index or resolver state enters the resulting root.
podman exec "$CONTAINER" chroot "/out/$TMP_BASE" /bin/sh -ec '
    /sbin/apk add --no-network /tmp/apks/*.apk
    rm -rf /tmp/apks /var/cache/apk/* /var/log/apk.log
'

install -m 0755 "$ROOT/scripts/t6040-b0-autologin" \
    "$TMP/usr/local/sbin/t6040-b0-autologin"
install -m 0755 "$ROOT/scripts/t6040-b0-ttydc0-console" \
    "$TMP/usr/local/sbin/t6040-b0-ttydc0-console"
install -m 0755 "$ROOT/scripts/t6040-b0-health-report" \
    "$TMP/usr/local/sbin/t6040-b0-health-report"
install -m 0755 "$ROOT/scripts/t6040-b0-watchdog.initd" \
    "$TMP/etc/init.d/t6040-watchdog"
install -m 0755 "$ROOT/scripts/t6040-b0-health-report.initd" \
    "$TMP/etc/init.d/t6040-health-report"

cat >"$TMP/etc/inittab" <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
::shutdown:/sbin/openrc shutdown
tty0::respawn:/sbin/getty -n -l /usr/local/sbin/t6040-b0-autologin 38400 tty0 linux
::respawn:/usr/local/sbin/t6040-b0-ttydc0-console
EOF
printf 'wallace-b0\n' >"$TMP/etc/hostname"
: >"$TMP/etc/fstab"
: >"$TMP/etc/modules"
rm -rf "$TMP/etc/network" "$TMP/etc/udhcpc"
rm -f "$TMP/etc/resolv.conf"

# Root stays cryptographically locked; the two physically local gettys invoke
# the explicit diagnostic shell directly. There is no password or secret.
sed -i.bak 's|^root:[^:]*:|root:!:|' "$TMP/etc/shadow"
rm -f "$TMP/etc/shadow.bak"

rm -rf "$TMP/etc/runlevels"
install -d \
    "$TMP/etc/runlevels/sysinit" \
    "$TMP/etc/runlevels/boot" \
    "$TMP/etc/runlevels/default" \
    "$TMP/etc/runlevels/shutdown"
ln -s /etc/init.d/devfs "$TMP/etc/runlevels/sysinit/devfs"
ln -s /etc/init.d/dmesg "$TMP/etc/runlevels/sysinit/dmesg"
ln -s /etc/init.d/procfs "$TMP/etc/runlevels/sysinit/procfs"
ln -s /etc/init.d/sysfs "$TMP/etc/runlevels/sysinit/sysfs"
ln -s /etc/init.d/hostname "$TMP/etc/runlevels/boot/hostname"
ln -s /etc/init.d/sysctl "$TMP/etc/runlevels/boot/sysctl"
ln -s /etc/init.d/t6040-watchdog \
    "$TMP/etc/runlevels/default/t6040-watchdog"
ln -s /etc/init.d/t6040-health-report \
    "$TMP/etc/runlevels/default/t6040-health-report"

if find "$TMP" -type b -print -quit | grep -q .; then
    echo "B0 source unexpectedly contains a block-device node" >&2
    exit 1
fi
if find "$TMP/etc/runlevels" -type l \
        \( -name networking -o -name networkmanager -o -name wpa_supplicant \) \
        -print -quit | grep -q .; then
    echo "B0 runlevels unexpectedly enable networking" >&2
    exit 1
fi
grep -q '^root:!:' "$TMP/etc/shadow"
grep -qx 'aarch64' "$TMP/etc/apk/arch"
file "$TMP/bin/busybox" | grep -Eq 'ARM aarch64|ARM64'

awk '
    /^P:/ { package=substr($0, 3) }
    /^V:/ { print package "=" substr($0, 3) }
' "$TMP/lib/apk/db/installed" | LC_ALL=C sort >"$PACKAGES"

(
    cd "$TMP"
    find . -print0 | LC_ALL=C sort -z | xargs -0 stat -f '%z %N'
) >"$SIZES"

python3 "$ROOT/scripts/reproducible-newc.py" "$TMP" |
    gzip -n -9 >"$DEST_TMP"
gzip -t "$DEST_TMP"
chmod 0644 "$DEST_TMP"
mv "$DEST_TMP" "$DEST"
gzip -dc "$DEST" | cpio -it 2>/dev/null | LC_ALL=C sort >"$CONTENTS"

for required in \
    ./sbin/init \
    ./sbin/openrc \
    ./etc/init.d/t6040-watchdog \
    ./etc/init.d/t6040-health-report \
    ./etc/runlevels/default/t6040-watchdog \
    ./usr/local/sbin/t6040-b0-autologin \
    ./usr/local/sbin/t6040-b0-ttydc0-console
do
    grep -qx "$required" "$CONTENTS" || {
        echo "missing B0 entry: $required" >&2
        exit 1
    }
done

{
    echo "source_url=$ALPINE_URL"
    echo "source_sha256=$ALPINE_SHA256"
    echo "arch=$ALPINE_ARCH"
    echo "storage_disabled_required=true"
    echo "network_runlevels=none"
    echo "root_password=locked"
    shasum -a 256 "$DEST" "$CONTENTS" "$PACKAGES" "$SIZES"
} >"$MANIFEST"

echo "B0 Alpine/OpenRC RAM distro built:"
cat "$MANIFEST"
ls -lh "$DEST" "$CONTENTS" "$PACKAGES" "$SIZES" "$MANIFEST"
