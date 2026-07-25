#!/usr/bin/env bash
# Build an Alpine RAM root with Xorg + dwm for the T6040 graphical target (ticket 142).
#
# Unlike scripts/t6040-build-alpine-b0.sh (network-free, hash-pinned main-only release
# root), this experiment installs from the network inside the build container and then
# strips resolver/cache state. Pin exact versions once the image is proven to boot.
set -euo pipefail

OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
CONTAINER=${CONTAINER:-kbuild}
ALPINE_VERSION=3.24.0
ALPINE_ARCH=aarch64
ALPINE_FILE="alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
ARCHIVE="$OUT/$ALPINE_FILE"
DEST=${DEST:-"$OUT/initramfs-alpine-dwm.cpio.xz"}

[ -f "$ARCHIVE" ] || { echo "missing $ARCHIVE" >&2; exit 1; }

TMP=$(mktemp -d "$OUT/alpine-dwm.XXXXXX")
TMP_BASE=$(basename "$TMP")
trap 'podman exec "$CONTAINER" rm -rf "/out/$TMP_BASE" >/dev/null 2>&1 || true' EXIT

LC_ALL=C bsdtar -xf "$ARCHIVE" -C "$TMP"
install -d "$TMP/etc/apk" "$TMP/usr/local/sbin" "$TMP/etc/X11"
cat > "$TMP/etc/apk/repositories" <<EOF
https://dl-cdn.alpinelinux.org/alpine/v3.24/main
https://dl-cdn.alpinelinux.org/alpine/v3.24/community
EOF
cp /etc/resolv.conf "$TMP/etc/resolv.conf" 2>/dev/null || echo "nameserver 1.1.1.1" > "$TMP/etc/resolv.conf"

echo "== installing Xorg + dwm inside the container chroot =="
podman exec "$CONTAINER" chroot "/out/$TMP_BASE" /bin/sh -ec '
    apk update -q
    apk add --no-cache openrc busybox-openrc kbd-bkeymaps \
        xorg-server xf86-input-libinput xinit setxkbmap xrandr \
        dwm st dmenu font-terminus ttf-dejavu
    rm -rf /var/cache/apk/* /var/log/apk.log /etc/resolv.conf
'

# Trim what a software-framebuffer tiling WM cannot use. Verified with objdump: Xorg
# links nothing from LLVM/gallium, modesetting_drv.so needs only libgbm, and dwm/st
# need no GL — LLVM/gallium exist solely for DRI/llvmpipe rendering, which
# AccelMethod "none" never invokes. libLLVM alone is 181 MiB of a 293 MiB image.
echo "== trimming GL/JIT and surplus fonts =="
du -sm "$TMP" | awk '{print "  before: "$1" MiB"}'
rm -f  "$TMP"/usr/lib/libLLVM.so* "$TMP"/usr/lib/libgallium*.so*        "$TMP"/usr/lib/libSPIRV-Tools*.so* "$TMP"/usr/lib/libLLVMSPIRVLib*.so*
rm -rf "$TMP"/usr/lib/dri "$TMP"/usr/lib/xorg/modules/dri
# st resolves its default font through fontconfig, so keep Liberation; drop the rest.
rm -rf "$TMP"/usr/share/fonts/ttf-dejavu "$TMP"/usr/share/fonts/misc        "$TMP"/usr/share/fonts/font-misc-misc
rm -rf "$TMP"/usr/share/doc "$TMP"/usr/share/man "$TMP"/usr/share/info        "$TMP"/usr/share/licenses "$TMP"/usr/share/gtk-doc
du -sm "$TMP" | awk '{print "  after:  "$1" MiB"}'

# Xorg on simpledrm: modesetting with no acceleration, and do not require a pointer.
cat > "$TMP/etc/X11/xorg.conf" <<'EOF'
Section "ServerFlags"
    Option "AutoAddGPU"      "false"
    Option "AllowMouseOpenFail" "true"
EndSection
Section "Device"
    Identifier  "simpledrm"
    Driver      "modesetting"
    Option      "AccelMethod" "none"
    Option      "ShadowFB"    "true"
EndSection
EOF

# start X on the panel with dwm; Norwegian layout via setxkbmap (dwm keybinds are
# compile-time, so the layout is set in X rather than rebuilding dwm).
cat > "$TMP/usr/local/sbin/t6040-startx" <<'EOF'
#!/bin/sh
export HOME=/root XAUTHORITY=/tmp/.Xauth
: > "$XAUTHORITY"
cat > /root/.xinitrc <<'XEOF'
setxkbmap no || true
xrandr --dpi 192 2>/dev/null || true
st &
exec dwm
XEOF
exec startx -- vt1 -keeptty > /var/log/xorg-startx.log 2>&1
EOF
chmod 0755 "$TMP/usr/local/sbin/t6040-startx"

printf 'wallace-dwm\n' > "$TMP/etc/hostname"
: > "$TMP/etc/fstab"
sed -i.bak 's|^root:[^:]*:|root::|' "$TMP/etc/shadow" && rm -f "$TMP/etc/shadow.bak"
cat > "$TMP/etc/inittab" <<'EOF'
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
::sysinit:/bin/mount -t devtmpfs devtmpfs /dev
::sysinit:/bin/mkdir -p /dev/pts /tmp /run /var/log
::sysinit:/bin/mount -t devpts devpts /dev/pts
::sysinit:/bin/sh -c 'busybox loadkmap < /usr/share/bkeymaps/no/no-mac.bmap 2>/dev/null || true'
::once:/usr/local/sbin/t6040-startx
tty1::respawn:/sbin/getty -n -l /bin/sh 38400 tty1 linux
::ctrlaltdel:/sbin/reboot
EOF
ln -sf /bin/busybox "$TMP/sbin/init" 2>/dev/null || true

python3 "$(dirname "$0")/reproducible-newc.py" "$TMP" | xz -9e --check=crc32 -T1 > "$DEST"
echo "built $DEST"
python3 - "$DEST" <<'PY'
import hashlib, os, sys
p = sys.argv[1]; d = open(p,'rb').read()
print(f"  {os.path.getsize(p):,} B ({os.path.getsize(p)/1048576:.2f} MiB)  sha256 {hashlib.sha256(d).hexdigest()}")
PY
