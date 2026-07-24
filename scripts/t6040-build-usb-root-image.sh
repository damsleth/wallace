#!/usr/bin/env bash
# Build a flash-ready GPT/ext4 Alpine image without touching a block device.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
POPULATE="$ROOT/scripts/t6040-populate-usb-rootfs.sh"
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
ALPINE=${ALPINE:-"$OUT/alpine-minirootfs-3.24.0-aarch64.tar.gz"}
IMAGE=${IMAGE:-"$OUT/t6040-alpine-usb-root.img"}
MANIFEST=${MANIFEST:-"$OUT/t6040-alpine-usb-root.manifest"}
SIZE_MIB=${SIZE_MIB:-1024}
MODULES=
FIRMWARE=
CONTAINER_IMAGE=${CONTAINER_IMAGE:-docker.io/library/fedora:41}

usage() {
    cat <<'EOF'
Usage: t6040-build-usb-root-image.sh [options]

Options:
  --image FILE       Output raw GPT image
  --manifest FILE    Output identity/hash manifest
  --size-mib N       Sparse image size (default: 1024)
  --alpine FILE      Pinned Alpine aarch64 minirootfs
  --modules DIR      Optional matching modules tree
  --firmware DIR     Optional paired firmware tree

The output is a regular file. This script never opens or writes a block device.
It refuses to overwrite either output. Flashing remains a separate, explicit,
whole-disk operation after the removable target has been identified.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image) IMAGE=$2; shift 2 ;;
        --manifest) MANIFEST=$2; shift 2 ;;
        --size-mib) SIZE_MIB=$2; shift 2 ;;
        --alpine) ALPINE=$2; shift 2 ;;
        --modules) MODULES=$2; shift 2 ;;
        --firmware) FIRMWARE=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

case "$SIZE_MIB" in
    ''|*[!0-9]*) die "--size-mib must be an integer" ;;
esac
[ "$SIZE_MIB" -ge 128 ] || die "--size-mib must be at least 128"
[ -f "$ALPINE" ] || die "Alpine archive not found: $ALPINE"
[ ! -e "$IMAGE" ] || die "refusing to overwrite image: $IMAGE"
[ ! -e "$MANIFEST" ] || die "refusing to overwrite manifest: $MANIFEST"
command -v podman >/dev/null 2>&1 || die "podman is required"
command -v uuidgen >/dev/null 2>&1 || die "uuidgen is required"

mkdir -p "$(dirname "$IMAGE")" "$(dirname "$MANIFEST")"
IMAGE_DIR=$(cd "$(dirname "$IMAGE")" && pwd -P)
IMAGE="$IMAGE_DIR/$(basename "$IMAGE")"
WORK=$(mktemp -d "$IMAGE_DIR/.t6040-usb-image.XXXXXX")
BUILD_COMPLETE=0
cleanup() {
    if [ "$BUILD_COMPLETE" -ne 1 ] && [ -f "$IMAGE" ]; then
        rm -f "$IMAGE"
    fi
    case "$WORK" in
        "$IMAGE_DIR"/.t6040-usb-image.*) rm -rf "$WORK" ;;
        *) echo "WARNING: refusing unexpected cleanup path: $WORK" >&2 ;;
    esac
}
trap cleanup EXIT

mkdir -p "$WORK/root" "$WORK/empty-modules" "$WORK/empty-firmware"
MODULES=${MODULES:-"$WORK/empty-modules"}
FIRMWARE=${FIRMWARE:-"$WORK/empty-firmware"}
[ -d "$MODULES" ] || die "modules directory not found: $MODULES"
[ -d "$FIRMWARE" ] || die "firmware directory not found: $FIRMWARE"

DISK_GUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
PARTUUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
FSUUID=$(uuidgen | tr '[:upper:]' '[:lower:]')

"$POPULATE" stage \
    --root "$WORK/root" \
    --partuuid "$PARTUUID" \
    --alpine "$ALPINE" \
    --modules "$MODULES" \
    --firmware "$FIRMWARE" \
    --manifest "$WORK/rootfs.manifest"

cp "$WORK/rootfs.manifest" "$WORK/rootfs.manifest.input"
IMAGE_BASE=$(basename "$IMAGE")
WORK_BASE=$(basename "$WORK")

podman run --rm \
    -v "$IMAGE_DIR:/out" \
    "$CONTAINER_IMAGE" \
    bash -euxo pipefail -c '
        dnf -qy install gdisk e2fsprogs
        work=/out/'"$WORK_BASE"'
        image=/out/'"$IMAGE_BASE"'
        truncate -s '"$SIZE_MIB"'MiB "$image"
        sgdisk --clear \
            --disk-guid='"$DISK_GUID"' \
            --new=1:2048:0 \
            --typecode=1:8300 \
            --change-name=1:t6040root \
            --partition-guid=1:'"$PARTUUID"' \
            "$image"
        start=$(sgdisk -i 1 "$image" |
            sed -n "s/^First sector: *\\([0-9][0-9]*\\).*/\\1/p")
        end=$(sgdisk -i 1 "$image" |
            sed -n "s/^Last sector: *\\([0-9][0-9]*\\).*/\\1/p")
        test -n "$start"
        test -n "$end"
        sectors=$((end - start + 1))
        truncate -s $((sectors * 512)) "$work/root.ext4"
        mkfs.ext4 -q -F -L t6040root -U '"$FSUUID"' \
            -d "$work/root" "$work/root.ext4"
        e2fsck -fn "$work/root.ext4"
        dd if="$work/root.ext4" of="$image" bs=512 seek="$start" \
            conv=notrunc,sparse status=none
        sgdisk -v "$image"
        sgdisk -i 1 "$image"
    '

IMAGE_SHA256=$(sha256_file "$IMAGE")
{
    echo "format=t6040-usb-root-image-v1"
    echo "image=$(basename "$IMAGE")"
    echo "image_size_bytes=$(stat -f %z "$IMAGE")"
    echo "image_sha256=$IMAGE_SHA256"
    echo "disk_guid=$DISK_GUID"
    echo "partition_guid=$PARTUUID"
    echo "filesystem_uuid=$FSUUID"
    echo "filesystem_label=t6040root"
    echo "root_bootarg=root=PARTUUID=$PARTUUID rootfstype=ext4 rootwait"
    echo "alpine_archive=$(basename "$ALPINE")"
    echo "alpine_sha256=$(sha256_file "$ALPINE")"
    echo
    cat "$WORK/rootfs.manifest.input"
} >"$MANIFEST"
BUILD_COMPLETE=1

echo "Built flash-ready T6040 Alpine image: $IMAGE"
echo "SHA-256: $IMAGE_SHA256"
echo "Manifest: $MANIFEST"
echo "Bootargs: root=PARTUUID=$PARTUUID rootfstype=ext4 rootwait"
