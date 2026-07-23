#!/usr/bin/env bash
# Prepare the Alpine aarch64 external root filesystem for T6040/J614s.
#
# "stage" is host-safe and populates an explicitly empty directory. "device"
# is destructive and intentionally Linux-only, root-only, removable-disk-only,
# and protected by an exact confirmation string.
set -euo pipefail

ALPINE_SHA256_DEFAULT=4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a
LABEL=t6040root
MODE=
ALPINE=
ALPINE_SHA256=$ALPINE_SHA256_DEFAULT
MODULES=
FIRMWARE=
ROOT=
DEVICE=
PARTUUID=
FSUUID=
DISK_GUID=
MANIFEST=
CONFIRM=

usage() {
    cat <<'EOF'
Usage:
  t6040-populate-usb-rootfs.sh stage \
      --root EMPTY_DIR --partuuid UUID --alpine MINIRootfs.tar.gz \
      --modules MODULES_DIR --firmware FIRMWARE_DIR --manifest FILE

  sudo t6040-populate-usb-rootfs.sh device \
      --device /dev/sdX --confirm ERASE:/dev/sdX \
      --alpine MINIRootfs.tar.gz --modules MODULES_DIR \
      --firmware FIRMWARE_DIR --manifest FILE

Inputs:
  --modules DIR    Contents are copied below /lib/modules.
  --firmware DIR   Contents are copied below /lib/firmware.
  --alpine-sha256  Override the pinned Alpine 3.24.0 aarch64 minirootfs hash.

The device mode erases the entire named removable disk. It refuses mounted
devices, non-removable disks, partition paths, non-Linux hosts, non-root users,
and any confirmation other than the literal ERASE:<device>.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        need shasum
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

uuid_lower() {
    tr '[:upper:]' '[:lower:]'
}

tree_manifest() {
    local source=$1
    local prefix=$2
    local entry rel digest target

    while IFS= read -r -d '' entry; do
        rel=${entry#"$source"/}
        if [ -L "$entry" ]; then
            target=$(readlink "$entry")
            printf 'link  %s/%s -> %s\n' "$prefix" "$rel" "$target"
        elif [ -f "$entry" ]; then
            digest=$(sha256_file "$entry")
            printf 'file  %s  %s/%s\n' "$digest" "$prefix" "$rel"
        fi
    done < <(find "$source" \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
}

copy_tree() {
    local source=$1
    local destination=$2

    mkdir -p "$destination"
    # `source/.` also copies dotfiles and preserves symlinks/modes.
    cp -a "$source/." "$destination/"
}

write_root_config() {
    local root=$1
    local partuuid=$2

    mkdir -p "$root/etc" "$root/lib/modules" "$root/lib/firmware"
    cat >"$root/etc/fstab" <<EOF
PARTUUID=$partuuid / ext4 defaults,noatime 0 1
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
EOF
    printf '%s\n' t6040-alpine >"$root/etc/hostname"
    cat >"$root/etc/motd" <<'EOF'
T6040/J614s external-root bring-up image
Internal NVMe is intentionally absent from the Linux device tree.
EOF
}

validate_inputs() {
    [ -n "$ALPINE" ] || die "--alpine is required"
    [ -f "$ALPINE" ] || die "Alpine archive not found: $ALPINE"
    [ -n "$MODULES" ] || die "--modules is required"
    [ -d "$MODULES" ] || die "modules directory not found: $MODULES"
    [ -n "$FIRMWARE" ] || die "--firmware is required"
    [ -d "$FIRMWARE" ] || die "firmware directory not found: $FIRMWARE"
    [ -n "$MANIFEST" ] || die "--manifest is required"

    local actual
    actual=$(sha256_file "$ALPINE")
    [ "$actual" = "$ALPINE_SHA256" ] ||
        die "Alpine SHA-256 mismatch: expected $ALPINE_SHA256, got $actual"
}

populate_root() {
    local root=$1
    local partuuid=$2

    need tar
    tar --numeric-owner -xpf "$ALPINE" -C "$root"
    # Alpine's /sbin/init is an absolute /bin/busybox symlink. On a non-Linux
    # staging host, testing it with -x follows the host's /bin instead.
    [ -L "$root/sbin/init" ] || [ -x "$root/sbin/init" ] ||
        die "Alpine archive did not provide /sbin/init"
    [ -x "$root/bin/busybox" ] ||
        die "Alpine archive did not provide executable /bin/busybox"
    [ -e "$root/lib/ld-musl-aarch64.so.1" ] ||
        die "Alpine archive is not the expected aarch64 minirootfs"

    copy_tree "$MODULES" "$root/lib/modules"
    copy_tree "$FIRMWARE" "$root/lib/firmware"
    write_root_config "$root" "$partuuid"
}

write_manifest() {
    local root=$1
    local mode=$2
    local partuuid=$3
    local fsuuid=$4
    local disk_guid=$5
    local alpine_hash
    local manifest_tmp

    alpine_hash=$(sha256_file "$ALPINE")
    manifest_tmp=$(mktemp "${TMPDIR:-/tmp}/t6040-rootfs-manifest.XXXXXX")
    {
        echo "format=t6040-usb-rootfs-v1"
        echo "mode=$mode"
        echo "label=$LABEL"
        echo "partuuid=$partuuid"
        echo "filesystem_uuid=$fsuuid"
        echo "disk_guid=$disk_guid"
        echo "root_bootarg=root=PARTUUID=$partuuid rootfstype=ext4 rootwait"
        echo "alpine_archive=$(basename "$ALPINE")"
        echo "alpine_sha256=$alpine_hash"
        echo
        echo "[modules]"
        tree_manifest "$root/lib/modules" lib/modules
        echo
        echo "[firmware]"
        tree_manifest "$root/lib/firmware" lib/firmware
        echo
        echo "[base-identity]"
        sha256_file "$root/etc/alpine-release" |
            awk '{print "file  "$1"  etc/alpine-release"}'
        printf 'link  sbin/init -> %s\n' "$(readlink "$root/sbin/init")"
        sha256_file "$root/bin/busybox" |
            awk '{print "file  "$1"  bin/busybox"}'
        sha256_file "$root/etc/fstab" |
            awk '{print "file  "$1"  etc/fstab"}'
    } >"$manifest_tmp"
    mkdir -p "$(dirname "$MANIFEST")"
    mv "$manifest_tmp" "$MANIFEST"
}

stage_mode() {
    [ -n "$ROOT" ] || die "stage mode requires --root"
    [ -n "$PARTUUID" ] || die "stage mode requires --partuuid"
    [ -d "$ROOT" ] || die "stage root must be an existing empty directory: $ROOT"
    [ -z "$(find "$ROOT" -mindepth 1 -print -quit)" ] ||
        die "stage root is not empty: $ROOT"

    local resolved
    resolved=$(cd "$ROOT" && pwd -P)
    case "$resolved" in
        /|"$HOME"|/Users|/home|/root) die "unsafe stage root: $resolved" ;;
    esac
    ROOT=$resolved
    populate_root "$ROOT" "$PARTUUID"
    write_manifest "$ROOT" stage "$PARTUUID" not-applicable not-applicable
    echo "Staged T6040 rootfs: $ROOT"
    echo "Manifest: $MANIFEST"
    echo "Bootargs: root=PARTUUID=$PARTUUID rootfstype=ext4 rootwait"
}

device_partition_path() {
    lsblk -nrpo NAME,TYPE "$DEVICE" |
        awk '$2 == "part" {print $1; exit}'
}

device_mode() {
    [ "$(uname -s)" = Linux ] || die "device mode is Linux-only"
    [ "$(id -u)" -eq 0 ] || die "device mode must run as root"
    [ -n "$DEVICE" ] || die "device mode requires --device"
    [ "$CONFIRM" = "ERASE:$DEVICE" ] ||
        die "refusing erase: pass --confirm ERASE:$DEVICE"

    for command in lsblk findmnt wipefs sgdisk partprobe udevadm mkfs.ext4 \
        mount umount uuidgen; do
        need "$command"
    done
    [ -b "$DEVICE" ] || die "not a block device: $DEVICE"
    [ "$(lsblk -dnro TYPE "$DEVICE")" = disk ] ||
        die "--device must name a whole disk, not a partition"
    [ "$(lsblk -dnro RM "$DEVICE")" = 1 ] ||
        die "refusing non-removable disk: $DEVICE"
    if lsblk -nrpo MOUNTPOINT "$DEVICE" | grep -q '[^[:space:]]'; then
        die "device or a child partition is mounted: $DEVICE"
    fi
    if [ "$(findmnt -nro SOURCE /)" = "$DEVICE" ]; then
        die "refusing root disk: $DEVICE"
    fi

    DISK_GUID=${DISK_GUID:-$(uuidgen | uuid_lower)}
    PARTUUID=${PARTUUID:-$(uuidgen | uuid_lower)}
    FSUUID=${FSUUID:-$(uuidgen | uuid_lower)}

    echo "Erasing removable disk $DEVICE"
    wipefs --all "$DEVICE"
    sgdisk --zap-all "$DEVICE"
    sgdisk --disk-guid="$DISK_GUID" \
        --new=1:2048:0 --typecode=1:8300 --change-name=1:"$LABEL" \
        --partition-guid=1:"$PARTUUID" "$DEVICE"
    partprobe "$DEVICE"
    udevadm settle

    local partition mount_dir
    partition=$(device_partition_path)
    [ -n "$partition" ] || die "partition node did not appear for $DEVICE"
    mkfs.ext4 -F -L "$LABEL" -U "$FSUUID" "$partition"

    mount_dir=$(mktemp -d /tmp/t6040-rootfs.XXXXXX)
    cleanup_device() {
        if mountpoint -q "$mount_dir"; then
            umount "$mount_dir"
        fi
        rmdir "$mount_dir" 2>/dev/null || true
    }
    trap cleanup_device EXIT
    mount "$partition" "$mount_dir"
    populate_root "$mount_dir" "$PARTUUID"
    write_manifest "$mount_dir" device "$PARTUUID" "$FSUUID" "$DISK_GUID"
    sync
    umount "$mount_dir"
    rmdir "$mount_dir"
    trap - EXIT

    echo "Populated: $partition"
    echo "Manifest: $MANIFEST"
    echo "Bootargs: root=PARTUUID=$PARTUUID rootfstype=ext4 rootwait"
}

[ "$#" -gt 0 ] || {
    usage
    exit 2
}
MODE=$1
shift

while [ "$#" -gt 0 ]; do
    case "$1" in
        --alpine) ALPINE=$2; shift 2 ;;
        --alpine-sha256) ALPINE_SHA256=$2; shift 2 ;;
        --modules) MODULES=$2; shift 2 ;;
        --firmware) FIRMWARE=$2; shift 2 ;;
        --manifest) MANIFEST=$2; shift 2 ;;
        --root) ROOT=$2; shift 2 ;;
        --device) DEVICE=$2; shift 2 ;;
        --partuuid) PARTUUID=$2; shift 2 ;;
        --confirm) CONFIRM=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

case "$MODE" in
    stage)
        validate_inputs
        stage_mode
        ;;
    device)
        validate_inputs
        device_mode
        ;;
    *)
        die "mode must be stage or device"
        ;;
esac
