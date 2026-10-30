#!/usr/bin/env bash
# Build the ticket-5005 NVMe daily root image on the host: the pinned Alpine
# dwm/i3 desktop root (initramfs-alpine-dwm-i3-v5) with a persistent-root
# OpenRC profile and the Norwegian layout, as a 16 GiB ext4 (UUID 988d97b4)
# compressed with xz for the one-shot installer. Never opens a block device.
# SD64 (the original clone source) is unavailable (CJ, 2026-10-25).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/code/linux-build-out}
BASE=${BASE:-$OUT/initramfs-alpine-dwm-i3-v5.cpio.xz}
BASE_SHA256=25d4b110038a13eaea7ffe0019df6728c4b996d2f0ea12458fe391cecf7347ee
KEYMAP=${KEYMAP:-$OUT/no-latin1.bmap}
KEYMAP_SHA256=606ecd98f83b72983f3cd35976df939dc9c7187283703736a81e89b65aee85a8
# 5022: packages added live on the 2026-10-30 standalone root, pinned to the
# versions that ran there. NO_EXTRA_APKS=1 skips them (offline rebuild).
EXTRA_APKS=${EXTRA_APKS-"chrony=4.8-r7 openssh-server=10.3_p1-r1 jq=1.8.2-r0 perl=5.42.2-r1 kexec-tools=2.0.32-r2"}
[ "${NO_EXTRA_APKS:-0}" = 1 ] && EXTRA_APKS=""
# Root sshd is key-only and enabled only when a public key is given.
AUTHORIZED_KEYS=${AUTHORIZED_KEYS:-}
DEST=${DEST:?set DEST to the output directory}
ROOT_UUID=988d97b4-06ba-40d7-8f70-7899bb6fa297
ROOT_BYTES=17179869184
[ ! -e "$DEST" ] || { echo "refusing to overwrite $DEST" >&2; exit 1; }
printf '%s  %s\n' "$BASE_SHA256" "$BASE" "$KEYMAP_SHA256" "$KEYMAP" | shasum -a 256 -c -
mkdir -p "$DEST"
cp "$BASE" "$DEST/base.cpio.xz"
cp "$KEYMAP" "$DEST/wallace-no.bmap"
cp "$ROOT/scripts/t6040-usb-root-keymap.initd" "$DEST/t6040-keymap.initd"
if [ -n "$AUTHORIZED_KEYS" ]; then cp "$AUTHORIZED_KEYS" "$DEST/authorized_keys"; fi
D=$(cd "$DEST" && pwd -P)

# The container script goes through a file: podman machine ssh joins its
# arguments, so an inline sh -c script would run partly on the VM.
cat >"$DEST/build.sh" <<EOS
set -eu
ROOT_BYTES=$ROOT_BYTES
ROOT_UUID=$ROOT_UUID
EXTRA_APKS="$EXTRA_APKS"
EOS
cat >>"$DEST/build.sh" <<'EOS'
    apk add -q e2fsprogs e2fsprogs-extra xz cpio >/dev/null
    W=/var/tmp/nvmeroot; rm -rf $W; mkdir -p $W/r
    cd $W/r && xz -dc /d/base.cpio.xz | cpio -idm --quiet 2>/dev/null
    [ "$(cat etc/alpine-release)" = 3.24.0 ] && [ -x sbin/openrc ] && [ -x usr/libexec/Xorg ]
    rm -f init etc/machine-id
    # The RAM-root helper polls and mounts every NVMe partition read-write;
    # the nvmeroot init owns p3, so it and its sync partner must not exist.
    rm -f usr/local/sbin/t6040-data-mount usr/local/sbin/t6040-data-sync
    # 5022: extra packages, installed by the root's own apk so its database
    # format and maintainer scripts match.
    if [ -n "$EXTRA_APKS" ]; then
        [ ! -e etc/resolv.conf ] || mv etc/resolv.conf etc/resolv.conf.wallace-keep
        cp /etc/resolv.conf etc/resolv.conf
        chroot . /sbin/apk add --no-cache --no-progress $EXTRA_APKS
        rm -f etc/resolv.conf
        [ ! -e etc/resolv.conf.wallace-keep ] || mv etc/resolv.conf.wallace-keep etc/resolv.conf
    fi
    # Persistent-root OpenRC profile; inittab and helpers come from the
    # nvmeroot initramfs every boot (sdroot design).
    rm -rf etc/runlevels; for l in sysinit boot default shutdown; do mkdir -p etc/runlevels/$l; done
    for s in sysinit:devfs sysinit:dmesg sysinit:procfs sysinit:sysfs boot:hostname boot:bootmisc \
             boot:swclock boot:t6040-keymap default:dbus default:bluetooth shutdown:killprocs shutdown:mount-ro; do
        l=${s%%:*}; n=${s#*:}
        [ "$n" = t6040-keymap ] || [ -f etc/init.d/$n ] || { echo "missing service $n"; exit 1; }
        ln -s /etc/init.d/$n etc/runlevels/$l/$n
    done
    # 5022: no RTC (macsmc RTC never binds), so swclock restores time at boot from
    # this seed, and chronyd alone (no busybox ntpd) disciplines the clock.
    mkdir -p var/lib/misc && touch -d 2026-10-30T00:00:00Z var/lib/misc/openrc-shutdowntime
    if [ -f etc/init.d/chronyd ]; then
        sed -i "s/^rtcsync/# rtcsync  (disabled: no RTC on this machine; swclock restores time at boot)/" etc/chrony/chrony.conf
        ln -s /etc/init.d/chronyd etc/runlevels/default/chronyd
    fi
    if [ -f /d/authorized_keys ] && [ -f etc/init.d/sshd ]; then
        install -d -m 0700 root/.ssh
        install -m 0600 /d/authorized_keys root/.ssh/authorized_keys
        mkdir -p etc/ssh/sshd_config.d
        printf "PermitRootLogin prohibit-password\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n" > etc/ssh/sshd_config.d/10-wallace.conf
        ln -s /etc/init.d/sshd etc/runlevels/default/sshd
    fi
    # iwd stays out of every runlevel: this kernel lacks its crypto (AF_ALG
    # hash/skcipher, KEY_DH_OPERATIONS). WiFi is wpa_supplicant via inittab.
    install -m 0755 /d/t6040-keymap.initd etc/init.d/t6040-keymap
    install -m 0644 /d/wallace-no.bmap etc/wallace-no.bmap
    echo "keymap=\"no\"" > etc/conf.d/keymaps
    mkdir -p etc/X11/xorg.conf.d etc/profile.d
    printf "Section \"InputClass\"\n    Identifier \"system-keyboard\"\n    MatchIsKeyboard \"on\"\n    Option \"XkbLayout\" \"no\"\nEndSection\n" \
        > etc/X11/xorg.conf.d/00-keyboard.conf
    printf "Section \"InputClass\"\n    Identifier \"touchpad natural scrolling\"\n    MatchIsTouchpad \"on\"\n    MatchDriver \"libinput\"\n    Option \"NaturalScrolling\" \"true\"\n    Option \"Tapping\" \"true\"\nEndSection\n" \
        > etc/X11/xorg.conf.d/30-touchpad.conf
    printf "export LANG=nb_NO.UTF-8\nexport LC_CTYPE=nb_NO.UTF-8\n" > etc/profile.d/wallace-locale.sh
    printf 'case ":$PATH:" in\n\t*":$HOME/.local/bin:"*) ;;\n\t*) [ -d "$HOME/.local/bin" ] && PATH="$PATH:$HOME/.local/bin" ;;\nesac\nexport PATH\n' > etc/profile.d/local-bin.sh
    echo wallace > etc/hostname
    echo "# / is the loop-mounted wallace-root.img, mounted by the nvmeroot init" > etc/fstab
    echo nvmeroot-5005-v3 > etc/wallace-root-profile
    cd $W
    truncate -s $ROOT_BYTES img
    E2FSPROGS_FAKE_TIME=1 mkfs.ext4 -q -F -L wallace-root -U $ROOT_UUID \
        -E lazy_itable_init=0,lazy_journal_init=0,hash_seed=$ROOT_UUID -d r img
    e2fsck -fn img
    dumpe2fs -h img 2>/dev/null | grep -E "^(Filesystem UUID|Filesystem state|Block count|Filesystem features)" > /d/dumpe2fs.txt
    sha256sum img | cut -d" " -f1 > /d/wallace-root.img.sha256
    xz -T0 -6 --check=crc32 -c img > /d/wallace-root.img.xz
    (cd r && find . | sort) > /d/tree.txt
    rm -rf $W
EOS
podman machine ssh -- sudo podman run --rm -v "$D:/d" docker.io/library/alpine:3.22 sh /d/build.sh
rm -f "$DEST/build.sh" "$DEST/base.cpio.xz" "$DEST/wallace-no.bmap" "$DEST/t6040-keymap.initd" "$DEST/authorized_keys"
echo "raw sha256: $(cat "$DEST/wallace-root.img.sha256")"
shasum -a 256 "$DEST/wallace-root.img.xz"
ls -la "$DEST/wallace-root.img.xz"
