#!/usr/bin/env bash
# t6040-make-usb-rootfs.sh — build a reproducible external ext4 root for the
# T6040 USB-root path (ticket 060; design: done/2026-07-14-t6040-usb-root-design.md).
#
# RECIPE ONLY. Do NOT run against a real disk until the USB-host SMOKE test
# proves a device enumerates and stays present >=10 s (BACKLOG gate; the passive
# right-side stick test showed root hubs but no child device — ATC/HPM physical
# link is unsolved, tickets 023/064). This script is the populate step that
# follows a passing smoke, kept ready and reviewable.
#
# It NEVER touches an internal device: it operates only on an explicitly named
# external block device or an image file, and refuses anything that looks like
# the boot/internal disk.
set -euo pipefail

: "${TARGET:?set TARGET=/dev/disk<N> (external only) OR TARGET=/path/to/image.img}"
: "${ROOTFS_TAR:?set ROOTFS_TAR=/path/to/alpine-or-debian-arm64-rootfs.tar.gz}"
LABEL="${LABEL:-t6040root}"
MODULES_DIR="${MODULES_DIR:-}"      # optional: kernel modules/ tree to install
FIRMWARE_DIR="${FIRMWARE_DIR:-}"    # optional: Asahi fw corpus (tickets 014/016/030)
SIZE_MB="${SIZE_MB:-8192}"          # image size when TARGET is a file

# --- safety: refuse internal/boot disks -------------------------------------
case "$TARGET" in
  /dev/disk0|/dev/disk0s*|/dev/disk1|/dev/disk1s*)
    echo "REFUSING: $TARGET looks like an internal/boot disk." >&2; exit 2;;
esac
if [ -b "$TARGET" ]; then
  # macOS: require the disk to be external + removable/USB
  if command -v diskutil >/dev/null 2>&1; then
    info=$(diskutil info "$TARGET" 2>/dev/null || true)
    echo "$info" | grep -qiE 'Device Location: *External|Protocol: *USB' || {
      echo "REFUSING: $TARGET is not reported External/USB by diskutil." >&2; exit 2; }
    echo "$info" | grep -qiE 'Internal: *Yes' && {
      echo "REFUSING: $TARGET reports Internal: Yes." >&2; exit 2; }
  fi
  echo "About to REPARTITION external block device $TARGET (LABEL=$LABEL)."
  read -r -p "Type the device path again to confirm: " confirm
  [ "$confirm" = "$TARGET" ] || { echo "aborted."; exit 1; }
  DEV="$TARGET"
else
  echo "== creating ${SIZE_MB}MB image at $TARGET =="
  dd if=/dev/zero of="$TARGET" bs=1m count=0 seek="$SIZE_MB" 2>/dev/null || \
    truncate -s "${SIZE_MB}M" "$TARGET"
  DEV="$TARGET"   # loop/attach handled by the OS-specific block below
fi

echo "== GPT + single ext4 root partition (LABEL=$LABEL) =="
# NOTE: exact partition/mkfs tooling differs by host OS. On Linux:
#   sgdisk -og "$DEV"; sgdisk -n1:0:0 -t1:8300 -c1:linux "$DEV"; partprobe "$DEV"
#   mkfs.ext4 -L "$LABEL" "${DEV}1"     # record PARTUUID: blkid "${DEV}1"
# On macOS build hosts, populate the image via an arm64 container/VM with the
# Linux tools above (mkfs.ext4/blkid are not native). Keep this abstract so the
# reproducible build runs in the kbuild container, not on bare macOS.
echo "   (partition/mkfs performed in the Linux build container; see comment)"

echo "== populate base userland from $ROOTFS_TAR =="
echo "   tar -xzf \"$ROOTFS_TAR\" -C <mnt>   # arm64 base (Alpine/Debian) with /sbin/init"
[ -n "$MODULES_DIR" ] && echo "== install modules: cp -a \"$MODULES_DIR\" <mnt>/lib/modules =="
[ -n "$FIRMWARE_DIR" ] && echo "== stage Asahi firmware: cp -a \"$FIRMWARE_DIR\" <mnt>/lib/firmware =="

cat <<EOF

== NEXT ==
Record and pin: PARTUUID (\`blkid\`), LABEL=$LABEL, the rootfs tar SHA-256, and
the module/firmware manifest. Boot with the ROOT-mode initramfs
(scripts/t6040-init-usb-root, ROOT branch) and bootargs:
  root=PARTUUID=<uuid> rootfstype=ext4 rootwait console=ttydc0 maxcpus=1 idle=nop
The USB/storage stack is built-in (USB_DWC3_APPLE/XHCI/UAS/EXT4), so no modules
are needed to reach root. Gate: only after the SMOKE test passes on the rig.
EOF
