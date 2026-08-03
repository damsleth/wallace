#!/usr/bin/env bash
# Rebuild the hardened ticket-204 switch-root initramfs deterministically.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
BASE=${BASE:-$OUT/initramfs-sdroot-wifi-base-59764944.cpio.gz}
DEST=${DEST:-$OUT/initramfs-sdroot-hardened.cpio.gz}
BASE_SHA256=59764944c4aad38189df5ee05a190c5ce60fd44727482105e4f20df7d8c7edc1
TMP=$(mktemp -d "$OUT/sdroot-initramfs.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

[ -f "$BASE" ] || { echo "missing pinned base: $BASE" >&2; exit 1; }
printf '%s  %s\n' "$BASE_SHA256" "$BASE" | shasum -a 256 -c -

LC_ALL=C gzip -dc "$BASE" | (cd "$TMP" && LC_ALL=C bsdtar -xf -)
install -m 0755 "$ROOT/scripts/t6040-sdroot-init" "$TMP/init"
install -m 0755 "$ROOT/scripts/t6040-sdroot-shutdown" "$TMP/shutdown"

# fsck.exfat repairs a dirty SD64 in place. Statically linked on purpose: this
# initramfs carries no libc and no dynamic loader, so a dynamic binary would
# drag glibc plus ld-linux into the boot path. Built from Debian's own
# exfatprogs 1.2.0-1+deb12u1 source in the arm64 kbuild container with
# `make LDFLAGS=-all-static`, then stripped.
FSCK=${FSCK:-$OUT/fsck.exfat}
FSCK_SHA256=d56b877d91e8e42a64cf8d8ad574ea425041f6fe117f0e52180f84ffad972790
[ -f "$FSCK" ] || { echo "missing static fsck.exfat: $FSCK" >&2; exit 1; }
printf '%s  %s\n' "$FSCK_SHA256" "$FSCK" | shasum -a 256 -c -
install -d -m 0755 "$TMP/sbin"
install -m 0755 "$FSCK" "$TMP/sbin/fsck.exfat"

# brcmfmac and hci_bcm4377 probe before switch_root, so their paired 25F84
# firmware must be in this initramfs rather than only on the Alpine root.
(cd "$TMP/lib/firmware" && printf '%s\n' \
    '7cfae8622feeb119c756ae707d26f3a94f1cde44becefacf27ecf1fdc586d93b  brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.bin' \
    'af8df65b766a6e2c450892819ecf8422289463e342aa748532c110032140f309  brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.clm_blob' \
    '9abb8c1afe0413339f5eca7706150c507a7bca5d244b0a4c6f79e4c28d2ce7cf  brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.sig' \
    '2ee489bb7b59b74bad259969344d513b7a6803e83f3563b2ce090df18f53a013  brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.txcap_blob' \
    '203251922cfcf95f2233290d75def5ae88e41dfda77af36d8426d9d6db1db3d9  brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.txt' \
    '842258ff94948558073010494f0d8f5ab6d1d539e1b07b7b37790ca4cd9c923e  brcm/brcmbt4388c2-apple,mriya-u.bin' \
    '6f0f1002c45ef7feffe03aef9f4927ecdfdac3baefafeffda742d51ff2752d29  brcm/brcmbt4388c2-apple,mriya-u.ptb' |
    shasum -a 256 -c -)

python3 "$ROOT/scripts/reproducible-newc.py" "$TMP" | gzip -n -9 >"$DEST"

for item in init shutdown bin/busybox sbin/fsck.exfat \
    lib/firmware/brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.bin \
    lib/firmware/brcm/brcmbt4388c2-apple,mriya-u.bin; do
    gzip -dc "$DEST" | cpio -it 2>/dev/null | grep -qx "./$item" || {
        echo "missing initramfs member: $item" >&2
        exit 1
    }
done

for item in init shutdown; do
    embedded=$(gzip -dc "$DEST" | bsdtar -xOf - "$item" | shasum -a 256 | awk '{print $1}')
    source=$(shasum -a 256 "$ROOT/scripts/t6040-sdroot-$item" | awk '{print $1}')
    [ "$embedded" = "$source" ] || { echo "$item hash mismatch" >&2; exit 1; }
done

echo "initramfs -> $DEST"
shasum -a 256 "$DEST"
