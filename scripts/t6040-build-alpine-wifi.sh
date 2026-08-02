#!/usr/bin/env bash
# Build a HEADLESS Alpine RAM root for testing WiFi/Bluetooth on the M4 Pro.
#
# Why this exists (2026-07-29, ticket 168): WiFi came up (wlan0 + phy0, firmware
# running) on the minimal dcuart busybox root, but that root has no `iw`, no
# `wpa_supplicant` and no DHCP client, so association could not be attempted.
# The dwm image has a richer userspace but is graphical -- it can only be driven
# at the panel. This root is deliberately headless: it puts a login shell on
# /dev/ttydc0 (reusing the proven B0 console/autologin helpers), so the whole
# scan/associate/DHCP sequence can be driven over the KIS tether with
# `printf 'cmd\n' > /tmp/m1n1`.
#
# Unlike scripts/t6040-build-alpine-b0.sh (offline, hash-pinned APKs) this
# installs from the network inside the build container, like the dwm script.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
CONTAINER=${CONTAINER:-kbuild}
ALPINE_VERSION=${ALPINE_VERSION:-3.24.0}
ALPINE_ARCH=aarch64
ARCHIVE="$OUT/alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
DEST=${DEST:-"$OUT/initramfs-alpine-wifi.cpio.gz"}
FW_SRC=${FW_SRC:-"$OUT/t6040-paired-fw-25F84/vendorfw/brcm"}

[ -f "$ARCHIVE" ] || { echo "missing $ARCHIVE" >&2; exit 1; }
[ -d "$FW_SRC" ] || { echo "missing BCM4388 firmware corpus: $FW_SRC" >&2; exit 1; }

TMP=$(mktemp -d "$OUT/alpine-wifi.XXXXXX")
TMP_BASE=$(basename "$TMP")
trap 'podman exec "$CONTAINER" rm -rf "/out/$TMP_BASE" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

LC_ALL=C bsdtar -xf "$ARCHIVE" -C "$TMP"
install -d "$TMP/etc/apk" "$TMP/usr/local/sbin" "$TMP/lib/firmware/brcm" "$TMP/root"
cat >"$TMP/etc/apk/repositories" <<EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/community
EOF
cp /etc/resolv.conf "$TMP/etc/resolv.conf" 2>/dev/null || \
    echo "nameserver 1.1.1.1" >"$TMP/etc/resolv.conf"

echo "== installing wifi/bt userspace in the container chroot =="
# iw + wpa_supplicant: association. dhcpcd + busybox udhcpc: addressing.
# bluez/bluez-btmgmt: bring hci0 up and scan. pciutils: lspci for evidence.
podman exec "$CONTAINER" chroot "/out/$TMP_BASE" /bin/sh -ec '
    apk update -q
    apk add --no-cache openrc busybox-openrc \
        iw wpa_supplicant wireless-tools dhcpcd \
        bluez bluez-deprecated pciutils iproute2 \
        openssh-server openssh-keygen
    rm -rf /var/cache/apk/* /var/log/apk.log /etc/resolv.conf
'

echo "== staging BCM4388 apple,mriya firmware =="
cp "$FW_SRC"/* "$TMP/lib/firmware/brcm/"
# CRITICAL, and the most surprising thing about this hardware: brcmfmac maps
# BCM4388 chip revision >= 4 to the *c0* filename
# (BRCMF_FW_ENTRY(BRCM_CC_4388_CHIP_ID, 0xFFFFFFF0, 4388C0)), but this rev-6
# silicon needs the *c2* blobs -- feeding it c0 content yields
# "brcmf_pcie_download_fw_nvram: FW failed to initialize" even with firmware
# present and DMA working. So publish the c2 content under the c0 names that
# the driver actually requests. board_types[2] is
# "<board>-<otp.module>-<otp.vendor>" = apple,mriya-WLMT-u, which is why these
# exact names matter. See done/2026-07-29-t6040-WIFI-AND-BLUETOOTH-WORKING.md.
for ext in bin clm_blob txcap_blob sig txt; do
    src="$TMP/lib/firmware/brcm/brcmfmac4388c2-pcie.apple,mriya.$ext"
    [ "$ext" = txt ] && src="$TMP/lib/firmware/brcm/brcmfmac4388c2-pcie.apple,mriya-WLMT-u.txt"
    [ -f "$src" ] || continue
    cp "$src" "$TMP/lib/firmware/brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.$ext"
done
# Bluetooth: hci_bcm4377 asks for the '-u' (USI module) name first, which is the
# variant the paired corpus carries, then the plain name; provide both.
cp "$TMP/lib/firmware/brcm/brcmbt4388c2-apple,mriya-u.bin" \
   "$TMP/lib/firmware/brcm/brcmbt4388c2-apple,mriya.bin" 2>/dev/null || true

install -m 0755 "$ROOT/scripts/t6040-b0-ttydc0-console" \
    "$TMP/usr/local/sbin/t6040-b0-ttydc0-console"
install -m 0755 "$ROOT/scripts/t6040-wifi-autologin" \
    "$TMP/usr/local/sbin/t6040-wifi-autologin"
install -m 0755 "$ROOT/scripts/t6040-wifi-report" \
    "$TMP/usr/local/sbin/t6040-wifi-report"

# The ttydc0 console helper execs getty with -l t6040-b0-autologin; point that
# name at this image's own autologin so the helper can be reused verbatim.
ln -sf t6040-wifi-autologin "$TMP/usr/local/sbin/t6040-b0-autologin"

# scripts/t6040-boot-dcuart.sh hardcodes `rdinit=/init` (its minimal busybox
# initramfs has one) and puts it LAST on the cmdline, so it cannot be overridden
# via EXTRA_BOOTARGS. Alpine's init is /sbin/init, so without this shim the
# kernel finds no init and produces NO console output at all -- which is exactly
# how the first boot of this image failed.
# --- SSH (headless access once WiFi is up) -------------------------------
# Only the PUBLIC key is baked in; public keys are not secrets. Host keys are
# generated on first boot instead of shipped, so no private key ever lands in a
# build artifact or in git. Password auth is off entirely.
SSH_PUBKEY=${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}
if [ -f "$SSH_PUBKEY" ]; then
    install -d -m 0700 "$TMP/root/.ssh"
    install -m 0600 "$SSH_PUBKEY" "$TMP/root/.ssh/authorized_keys"
    echo "== ssh: authorized_keys from $SSH_PUBKEY =="
else
    echo "WARNING: no SSH_PUBKEY at $SSH_PUBKEY — sshd will accept no logins" >&2
fi
install -d -m 0755 "$TMP/etc/ssh" "$TMP/var/empty"
# Alpine's openssh-server is built WITHOUT PAM (that is the separate
# openssh-server-pam package), so `UsePAM` is an unsupported option and sshd
# exits with "line N: Unsupported option UsePAM" -- which cost a boot on
# 2026-07-29. Same for the deprecated ChallengeResponseAuthentication. Keep this
# config to options the Alpine build actually accepts.
cat >"$TMP/etc/ssh/sshd_config" <<'EOF'
# Headless T6040 test root: key-only root login, nothing else.
Port 22
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PrintMotd no
Subsystem sftp /usr/lib/ssh/sftp-server
EOF

# --- WiFi auto-association (optional, PSK never enters the repo) ----------
# Supply a config built on the machine or on the host with:
#   wpa_passphrase 'SSID' 'PSK' > /tmp/wpa.conf
# then rebuild with WPA_CONF=/tmp/wpa.conf. Without it the image still has all
# the tools and can be associated by hand at the panel.
install -d -m 0755 "$TMP/etc/wpa_supplicant"
if [ -n "${WPA_CONF:-}" ] && [ -f "$WPA_CONF" ]; then
    { echo "p2p_disabled=1"; cat "$WPA_CONF"; } \
        > "$TMP/etc/wpa_supplicant/wpa_supplicant.conf"
    chmod 0600 "$TMP/etc/wpa_supplicant/wpa_supplicant.conf"
    echo "== wifi: auto-association baked in from $WPA_CONF (PSK not logged) =="
else
    # p2p_disabled=1 silences the harmless "Failed to create interface
    # p2p-dev-wlan0: -52" that brcmfmac produces (no nl80211 P2P *device*
    # support on this chip); association is unaffected either way.
    printf 'p2p_disabled=1\n' > "$TMP/etc/wpa_supplicant/wpa_supplicant.conf"
    echo "== wifi: no WPA_CONF given; associate by hand (tools are present) =="
fi

install -m 0755 "$ROOT/scripts/t6040-wifi-init" "$TMP/init"

# No inittab/openrc: /init above is the whole userspace bring-up. openrc's
# sysinit does not populate /dev under rdinit, which is what broke the first
# two attempts (panel showed "can't open /dev/tty0" and "ttydc0 absent").

# Root has no password set and no network services are enabled by default; the
# only logins are the two physically-local gettys.
sed -i 's/^root:[^:]*:/root:*:/' "$TMP/etc/shadow" 2>/dev/null || true

echo "== packing =="
python3 "$ROOT/scripts/reproducible-newc.py" "$TMP" | gzip -9 >"$DEST"
printf 'built %s (%d bytes)\n' "$DEST" "$(wc -c <"$DEST")"
gzip -dc "$DEST" | cpio -it 2>/dev/null | grep -cE '.' | \
    xargs printf 'entries: %s\n'
for want in ./sbin/wpa_supplicant ./usr/sbin/iw ./sbin/dhcpcd ./sbin/udhcpc \
            ./usr/sbin/sshd ./usr/bin/ssh-keygen ./etc/ssh/sshd_config \
            ./usr/bin/hciconfig ./usr/bin/bluetoothctl ./usr/bin/lspci \
            ./init ./usr/local/sbin/t6040-wifi-report \
            './lib/firmware/brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.bin' \
            './lib/firmware/brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.txt' \
            './lib/firmware/brcm/brcmbt4388c2-apple,mriya-u.bin'; do
    gzip -dc "$DEST" | cpio -it 2>/dev/null | grep -qxF "$want" \
        || { echo "MISSING from image: $want" >&2; exit 1; }
done
echo "all required members present"
shasum -a 256 "$DEST"
