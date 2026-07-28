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
# FAT=1 (ticket 155): build for capability, not size. Keeps llvmpipe/gallium/DRI and
# the full font set, and adds software GL. The trimming below was justified by an
# object-size ceiling that was never measured to exist (ticket 137 found none to
# 256 MiB, which was the probe limit and a policy number, not hardware) — and it cost
# the only graphical image its software GL, while the matching kernel diet cost it
# CONFIG_NET and therefore AF_UNIX, which killed Xorg outright (ticket 148).
FAT=${FAT:-0}
if [ "$FAT" = "1" ]; then
    DEST=${DEST:-"$OUT/initramfs-alpine-dwm-fat.cpio.xz"}
else
    DEST=${DEST:-"$OUT/initramfs-alpine-dwm.cpio.xz"}
fi

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
# FAT adds software GL (llvmpipe via mesa-dri-gallium) plus kbd for real loadkeys, and
# xdpyinfo/xev so a graphical failure can be diagnosed on the machine itself.
FAT_PKGS=""
[ "$FAT" = "1" ] && FAT_PKGS="mesa-dri-gallium mesa-gl mesa-gbm kbd xdpyinfo xev"
podman exec -e FAT_PKGS="$FAT_PKGS" "$CONTAINER" chroot "/out/$TMP_BASE" /bin/sh -ec '
    apk update -q
    apk add --no-cache openrc busybox-openrc kbd-bkeymaps eudev xrdb \
        xorg-server xf86-input-libinput xinit setxkbmap xrandr \
        dwm st dmenu font-terminus ttf-dejavu $FAT_PKGS
    rm -rf /var/cache/apk/* /var/log/apk.log /etc/resolv.conf
'

# Trim what a software-framebuffer tiling WM cannot use. Verified with objdump: Xorg
# links nothing from LLVM/gallium, modesetting_drv.so needs only libgbm, and dwm/st
# need no GL — LLVM/gallium exist solely for DRI/llvmpipe rendering, which
# AccelMethod "none" never invokes. libLLVM alone is 181 MiB of a 293 MiB image.
if [ "$FAT" = "1" ]; then
    echo "== FAT: keeping GL/JIT, DRI and fonts (no trimming) =="
    du -sm "$TMP" | awk '{print "  image: "$1" MiB"}'
    # Only docs/man go: they cannot affect behaviour, and keeping them buys nothing.
    rm -rf "$TMP"/usr/share/doc "$TMP"/usr/share/man "$TMP"/usr/share/info \
           "$TMP"/usr/share/licenses "$TMP"/usr/share/gtk-doc
    du -sm "$TMP" | awk '{print "  after docs/man drop: "$1" MiB"}'
else
echo "== trimming GL/JIT and surplus fonts =="
du -sm "$TMP" | awk '{print "  before: "$1" MiB"}'
rm -f  "$TMP"/usr/lib/libLLVM.so* "$TMP"/usr/lib/libgallium*.so*        "$TMP"/usr/lib/libSPIRV-Tools*.so* "$TMP"/usr/lib/libLLVMSPIRVLib*.so*
rm -rf "$TMP"/usr/lib/dri "$TMP"/usr/lib/xorg/modules/dri
# st resolves its default font through fontconfig, so keep Liberation; drop the rest.
rm -rf "$TMP"/usr/share/fonts/ttf-dejavu "$TMP"/usr/share/fonts/misc        "$TMP"/usr/share/fonts/font-misc-misc
rm -rf "$TMP"/usr/share/doc "$TMP"/usr/share/man "$TMP"/usr/share/info        "$TMP"/usr/share/licenses "$TMP"/usr/share/gtk-doc
du -sm "$TMP" | awk '{print "  after:  "$1" MiB"}'
fi

# Ticket 168: optionally stage the paired BCM4388 apple,mriya WiFi/BT firmware so the
# built-in brcmfmac finds it the moment PCIe link-up lands (regen recipe for the corpus:
# done/2026-07-14-t6040-bcm4388-fw-extract.md). Off by default until PCIe works — 4.7 MiB
# raw counts against the 128 MiB expanded-initramfs limit for no benefit before then.
if [ "${T6040_WIFI_FW:-0}" = "1" ]; then
    FW_SRC=${T6040_WIFI_FW_SRC:-/Users/damsleth/Code/linux-build-out/t6040-paired-fw-25F84/vendorfw/brcm}
    [ -f "$FW_SRC/brcmfmac4388c2-pcie.apple,mriya.bin" ] || {
        echo "T6040_WIFI_FW=1 but no BCM4388 firmware at $FW_SRC" >&2
        echo "regenerate the corpus first: done/2026-07-14-t6040-bcm4388-fw-extract.md" >&2
        exit 1
    }
    echo "== staging BCM4388 apple,mriya firmware from $FW_SRC =="
    mkdir -p "$TMP/lib/firmware/brcm"
    cp "$FW_SRC"/* "$TMP/lib/firmware/brcm/"
    du -sm "$TMP/lib/firmware" | awk '{print "  firmware: "$1" MiB"}'
fi

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
# dwm loaded on the first full-kernel run (2026-07-26) but NO input worked. Cause:
# xf86-input-libinput enumerates devices through libudev, and this image had libudev.so
# (pulled in as a dependency) but no udevd/udevadm at all, so the udev database was empty
# and Xorg auto-add found zero devices. eudev is now installed and started here, before X,
# which is the standard Alpine arrangement. Ticket 161.
LOG=/var/log/xorg-startx.log
export HOME=/root XAUTHORITY=/tmp/.Xauth
: > "$XAUTHORITY"
mkdir -p /run/udev

{
    echo "== starting udevd =="
    /sbin/udevd --daemon 2>&1 || /sbin/udevd -d 2>&1 || echo "udevd FAILED to start"
    /bin/udevadm trigger --type=subsystems --action=add 2>&1
    /bin/udevadm trigger --type=devices --action=add 2>&1
    /bin/udevadm settle --timeout=10 2>&1
    # Diagnostics first: every rig cycle costs a reboot, so make a failure readable in one
    # pass rather than needing another boot to ask "was the keyboard even there?".
    echo "== /proc/bus/input/devices =="
    cat /proc/bus/input/devices 2>&1
    echo "== /dev/input =="
    ls -l /dev/input 2>&1
    echo "== udevadm info for event0 =="
    /bin/udevadm info --query=property --name=/dev/input/event0 2>&1
} > "$LOG" 2>&1

# HiDPI. The panel is 3024x1964 on 14.2in = ~254 DPI, but X assumes 96, so everything
# renders about a quarter of its intended physical size (2026-07-26: "text size is
# extremely small"). Three separate mechanisms are needed, because they do not share a
# source of truth:
#   * the X server's own DPI (-dpi), which sets what the display reports;
#   * Xft.dpi, which is what Xft actually consults for POINT sizes — this is what scales
#     dwm's bar and dmenu, whose fonts are compile-time "monospace:size=10" (suckless
#     configs are baked in, so they cannot be changed without rebuilding those binaries);
#   * an explicit font for st, because Alpine's st is built with a PIXELSIZE font, and a
#     pixelsize is immune to any DPI setting. This is why the earlier `xrandr --dpi 192`
#     could never have fixed st.
# 192 = 2x the 96 baseline, the usual HiDPI convention; T6040_DPI overrides it.
DPI=${T6040_DPI:-192}
ST_PX=${T6040_ST_PIXELSIZE:-28}
cat > /root/.Xresources <<XRES
Xft.dpi: $DPI
Xft.antialias: true
Xft.hinting: true
Xft.rgba: rgb
Xcursor.size: 48
XRES
cat > /root/.xinitrc <<XEOF
xrdb -merge /root/.Xresources || true
setxkbmap no || true
xrandr --dpi $DPI 2>/dev/null || true
st -f 'monospace:pixelsize=$ST_PX' &
exec dwm
XEOF
exec startx -- vt1 -keeptty -dpi "$DPI" >> "$LOG" 2>&1
EOF
chmod 0755 "$TMP/usr/local/sbin/t6040-startx"

# USB-tether ethernet: CDC-ECM gadget on the device-mode port (ticket 173).
cp "$(dirname "$0")/t6040-usb-ecm-gadget.sh" "$TMP/usr/local/sbin/t6040-usb-ecm-gadget"
cp "$(dirname "$0")/t6040-usb-debug-gadget.sh" "$TMP/usr/local/sbin/t6040-usb-debug-gadget"
chmod 0755 "$TMP/usr/local/sbin/t6040-usb-debug-gadget"
cp "$(dirname "$0")/t6040-usb-acm-console.sh" "$TMP/usr/local/sbin/t6040-usb-acm-console"
chmod 0755 "$TMP/usr/local/sbin/t6040-usb-acm-console"
chmod 0755 "$TMP/usr/local/sbin/t6040-usb-ecm-gadget"

printf 'wallace-dwm\n' > "$TMP/etc/hostname"
: > "$TMP/etc/fstab"
sed -i.bak 's|^root:[^:]*:|root::|' "$TMP/etc/shadow" && rm -f "$TMP/etc/shadow.bak"
cat > "$TMP/etc/inittab" <<'EOF'
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
::sysinit:/bin/mount -t devtmpfs devtmpfs /dev
::sysinit:/bin/mkdir -p /dev/pts /tmp /run /var/log
::sysinit:/bin/mount -t devpts devpts /dev/pts
::sysinit:/bin/sh -c 'for m in /usr/share/bkeymaps/no/no-mac.bmap /usr/share/bkeymaps/no/no.bmap; do [ -f "$m" ] && busybox loadkmap < "$m" && exit 0; [ -f "$m.gz" ] && busybox zcat "$m.gz" | busybox loadkmap && exit 0; done; true'
::sysinit:/usr/local/sbin/t6040-usb-acm-console
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
