#!/usr/bin/env bash
# T6040 kernel build harness (runs INSIDE the arm64 Linux build container).
#
# Invocation from the host (script + patches must be visible in /out):
#   cp ~/Code/wallace/scripts/t6040-kbuild.sh ~/Code/wallace/patches/*.patch ~/Code/linux-build-out/
#   podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard kbuild \
#       bash /out/t6040-kbuild.sh image
#   podman exec -e DOCKCHANNEL=1 -e HID_RX_REARM=1 \
#       -e BUILD_DIR=/build/linux-hid-rx-rearm kbuild \
#       bash /out/t6040-kbuild.sh image
#   podman exec -e DOCKCHANNEL=1 -e HID_STATE_TRACE=1 \
#       -e BUILD_DIR=/build/linux-hid-state-trace kbuild \
#       bash /out/t6040-kbuild.sh image
#   podman exec -e DOCKCHANNEL=1 -e HID_STATE_TRACE=1 -e HID_TYPE_FIX=1 \
#       -e BUILD_DIR=/build/linux-hid-type-fix kbuild \
#       bash /out/t6040-kbuild.sh image
#   podman exec -e DOCKCHANNEL=1 -e DOCKCHANNEL_EARLYCON=1 \
#       -e BUILD_DIR=/build/linux-dcuart-earlycon kbuild \
#       bash /out/t6040-kbuild.sh image
#   podman exec -e DOCKCHANNEL=1 -e DOCKCHANNEL_NBCON=1 \
#       -e BUILD_DIR=/build/linux-dcuart-nbcon kbuild \
#       bash /out/t6040-kbuild.sh image
# (The old /kbuild.sh bind mount predates the .plans refactor and is stale;
# exec via /out instead.)
# The mac host FS is case-insensitive, which corrupts kernel files (xt_CONNMARK.h
# vs xt_mark.h etc.), so we clone locally onto the container's case-sensitive FS
# (git objects are fine; only the mac working-tree checkout is corrupt), then copy
# in our uncommitted t6040 DT files.
#
#   /src : host ~/code/linux bind-mounted read-only (source of the clone + DT files)
#   /out : host artifacts dir bind-mounted read-write (Image + dtb land here)
#   /build : container-local (case-sensitive, fast)
set -euo pipefail

# Wallace's integration branch is based on AsahiLinux's asahi-wip and carries
# the T6040 DT, DockChannel, storage-DT, and parked USB gadget commit stack.
BRANCH="${BRANCH:-wallace/t6040-bringup}"
APPLE=arch/arm64/boot/dts/apple

echo "== deps =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential bc bison flex libssl-dev libelf-dev \
    python3 cpio kmod git >/dev/null

BUILD_DIR="${BUILD_DIR:-/build/linux}"

if [ ! -d "$BUILD_DIR/.git" ]; then
    echo "== clone (case-correct checkout) =="
    git clone --local --shared /src "$BUILD_DIR"
fi
cd "$BUILD_DIR"
git checkout -q "$BRANCH"

# Make independently cloned builds byte-reproducible. The kernel otherwise
# embeds the wall-clock compile time (and ambient container identity) in the
# Image even when source, config, System.map, and DTB are identical.
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(git show -s --format=%cI HEAD)}"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-wallace}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-t6040-kbuild}"
export KBUILD_BUILD_VERSION="${KBUILD_BUILD_VERSION:-1}"
export KCFLAGS="${KCFLAGS:+$KCFLAGS }-fdebug-prefix-map=$BUILD_DIR=/build/linux"
export KAFLAGS="${KAFLAGS:+$KAFLAGS }-fdebug-prefix-map=$BUILD_DIR=/build/linux"

echo "== copy in our t6040 DT files (uncommitted on host) =="
cp /src/$APPLE/t6040.dtsi        $APPLE/
cp /src/$APPLE/t6040-j614s.dts   $APPLE/
if [ -f /src/$APPLE/t6040-j614s-kbd.dts ]; then
    cp /src/$APPLE/t6040-j614s-kbd.dts $APPLE/
fi
if [ -f /src/$APPLE/t6040-j614s-kbd-infra.dts ]; then
    cp /src/$APPLE/t6040-j614s-kbd-infra.dts $APPLE/
fi
if [ -f /src/$APPLE/t6040-j614s-dcuart.dts ]; then
    cp /src/$APPLE/t6040-j614s-dcuart.dts $APPLE/
fi
if [ -f /src/$APPLE/t6040-j614s-dcuart-macsmc.dts ]; then
    cp /src/$APPLE/t6040-j614s-dcuart-macsmc.dts $APPLE/
fi
if [ "${USB_HOST:-0}" = "1" ]; then
    case "${USB_HOST_PORT:-all}" in
        all)
            USB_HOST_DTS=t6040-j614s-dcuart-usb-host.dts
            ;;
        left-front)
            USB_HOST_DTS=t6040-j614s-dcuart-usb-host-left-front.dts
            ;;
        right)
            USB_HOST_DTS=t6040-j614s-dcuart-usb-host-right.dts
            ;;
        *)
            echo "ERROR: USB_HOST_PORT must be all, left-front, or right"
            exit 1
            ;;
    esac
    if [ -f "/out/$USB_HOST_DTS" ]; then
        cp "/out/$USB_HOST_DTS" "$APPLE/"
    elif [ -f "/src/$APPLE/$USB_HOST_DTS" ]; then
        cp "/src/$APPLE/$USB_HOST_DTS" "$APPLE/"
    else
        echo "ERROR: USB_HOST=1 USB_HOST_PORT=${USB_HOST_PORT:-all} requires /out/$USB_HOST_DTS"
        exit 1
    fi
fi
if [ "${DOCKCHANNEL_IRQ_TEST:-0}" = "1" ]; then
    [ "${DOCKCHANNEL:-0}" = "1" ] || {
        echo "ERROR: DOCKCHANNEL_IRQ_TEST=1 requires DOCKCHANNEL=1"
        exit 1
    }
    for dts in t6040-j614s-dcuart.dts t6040-j614s-dcuart-irq.dts; do
        if [ ! -f "/out/$dts" ]; then
            echo "ERROR: DOCKCHANNEL_IRQ_TEST=1 requires /out/$dts"
            exit 1
        fi
        cp "/out/$dts" "$APPLE/"
    done
fi
if [ "${DOCKCHANNEL_IRQ_TX_POLL_TEST:-0}" = "1" ]; then
    [ "${DOCKCHANNEL_IRQ_TEST:-0}" = "1" ] || {
        echo "ERROR: DOCKCHANNEL_IRQ_TX_POLL_TEST=1 requires DOCKCHANNEL_IRQ_TEST=1"
        exit 1
    }
    dts=t6040-j614s-dcuart-irq-txpoll.dts
    if [ ! -f "/out/$dts" ]; then
        echo "ERROR: DOCKCHANNEL_IRQ_TX_POLL_TEST=1 requires /out/$dts"
        exit 1
    fi
    cp "/out/$dts" "$APPLE/"
fi
if [ "${HID_RX_REARM:-0}" = "1" ]; then
    [ "${DOCKCHANNEL:-0}" = "1" ] || {
        echo "ERROR: HID_RX_REARM=1 requires DOCKCHANNEL=1"
        exit 1
    }
    [ "${USB_HOST:-0}" = "0" ] || {
        echo "ERROR: HID_RX_REARM=1 is a storage-disabled diagnostic image"
        exit 1
    }
fi
if [ "${HID_STATE_TRACE:-0}" = "1" ]; then
    [ "${DOCKCHANNEL:-0}" = "1" ] || {
        echo "ERROR: HID_STATE_TRACE=1 requires DOCKCHANNEL=1"
        exit 1
    }
    [ "${USB_HOST:-0}" = "0" ] || {
        echo "ERROR: HID_STATE_TRACE=1 is a storage-disabled diagnostic image"
        exit 1
    }
    [ "${HID_RX_REARM:-0}" = "0" ] || {
        echo "ERROR: HID_STATE_TRACE=1 uses the unmodified receive control flow"
        exit 1
    }
fi
if [ "${HID_TYPE_FIX:-0}" = "1" ]; then
    [ "${DOCKCHANNEL:-0}" = "1" ] || {
        echo "ERROR: HID_TYPE_FIX=1 requires DOCKCHANNEL=1"
        exit 1
    }
    [ "${USB_HOST:-0}" = "0" ] || {
        echo "ERROR: HID_TYPE_FIX=1 is a storage-disabled candidate"
        exit 1
    }
fi
if [ "${TRACKPAD_MOTION:-0}" = "1" ]; then
    [ "${DOCKCHANNEL:-0}" = "1" ] || {
        echo "ERROR: TRACKPAD_MOTION=1 requires DOCKCHANNEL=1"
        exit 1
    }
    [ "${HID_TYPE_FIX:-0}" = "1" ] || {
        echo "ERROR: TRACKPAD_MOTION=1 requires HID_TYPE_FIX=1"
        exit 1
    }
    [ "${USB_HOST:-0}" = "0" ] || {
        echo "ERROR: TRACKPAD_MOTION=1 is a storage-disabled candidate"
        exit 1
    }
fi
if [ "${DOCKCHANNEL_EARLYCON:-0}" = "1" ]; then
    [ "${DOCKCHANNEL:-0}" = "1" ] || {
        echo "ERROR: DOCKCHANNEL_EARLYCON=1 requires DOCKCHANNEL=1"
        exit 1
    }
    [ "${USB_HOST:-0}" = "0" ] || {
        echo "ERROR: DOCKCHANNEL_EARLYCON=1 is a storage-disabled diagnostic"
        exit 1
    }
fi
if [ "${DOCKCHANNEL_NBCON:-0}" = "1" ]; then
    [ "${DOCKCHANNEL:-0}" = "1" ] || {
        echo "ERROR: DOCKCHANNEL_NBCON=1 requires DOCKCHANNEL=1"
        exit 1
    }
    [ "${DOCKCHANNEL_EARLYCON:-0}" = "0" ] || {
        echo "ERROR: choose DOCKCHANNEL_NBCON or DOCKCHANNEL_EARLYCON, not both"
        exit 1
    }
fi
if [ "${PCIE:-0}" = "1" ]; then
    if [ ! -f /out/t6040-j614s-dcuart-pcie.dts ]; then
        echo "ERROR: PCIE=1 requires /out/t6040-j614s-dcuart-pcie.dts"
        exit 1
    fi
    cp /out/t6040-j614s-dcuart-pcie.dts $APPLE/
fi
cp /src/$APPLE/t6040-pmgr.dtsi   $APPLE/
cp /src/$APPLE/Makefile          $APPLE/

echo "== apply flokli's t6040 CODE patches (aic locked-sysreg skip + idle=nop) =="
# CRITICAL: the build checks out COMMITTED code and only copies in DT files, so any
# uncommitted code edits on the host (e.g. the irq-apple-aic.c hyp-mode sysreg
# comment-out) are NOT in the build. Apply flokli's proven t6040 bring-up code
# patches here so they actually land. Patch disables BOTH the
# SYS_IMP_APL_VM_TMR_FIQ_ENA_EL2 and SYS_ICH_HCR_EL2 writes in aic_init_cpu (they
# trap on M4 raw-boot) and adds a working arm64 idle=[wfi|nop] param.
# Ticket 159: the DockChannel TTY driver (/dev/ttydc0) existed ONLY as untracked files
# inside the /build/linux-* trees — never in ~/Code/linux, never in patches/ — so a rebuild
# from a clean checkout silently produced a kernel with no ttydc0, losing the DockChannel
# shell and the transport the B0 health report reaches the host through. It is also why
# every kernel reported -dirty. Recovered byte-identically (sha256 2880e145, 464 lines) and
# applied here, BEFORE olddefconfig, so CONFIG_APPLE_DOCKCHANNEL_TTY is a real symbol rather
# than dead text that the DIET assertion would happily grep and pass.
if [ -f /out/t6040-dockchannel-tty-driver.patch ]; then
    if git apply --check /out/t6040-dockchannel-tty-driver.patch 2>/dev/null; then
        git apply /out/t6040-dockchannel-tty-driver.patch
        echo "t6040-dockchannel-tty-driver.patch applied OK"
    elif [ -f drivers/tty/apple_dockchannel_tty.c ]; then
        echo "t6040-dockchannel-tty-driver.patch already applied"
    else
        echo "ERROR: dockchannel TTY patch does not apply and the driver is absent:" >&2
        git apply --check /out/t6040-dockchannel-tty-driver.patch || true
        exit 1
    fi
elif [ ! -f drivers/tty/apple_dockchannel_tty.c ]; then
    echo "ERROR: no dockchannel TTY driver and no patch to add it." >&2
    echo "  /dev/ttydc0 would be absent, so the B0 health report cannot reach the host." >&2
    echo "  copy patches/t6040-dockchannel-tty-driver.patch into /out (see ticket 159)." >&2
    exit 1
fi

if git apply --check /out/flokli-code.patch 2>/dev/null; then
    git apply /out/flokli-code.patch
    echo "flokli-code.patch applied OK"
elif git apply -R --check /out/flokli-code.patch 2>/dev/null; then
    echo "flokli-code.patch already applied"
else
    echo "ERROR: flokli-code.patch does not apply cleanly to this tree:"
    git apply --check /out/flokli-code.patch || true
    echo "-- current aic_init_cpu hyp block (adapt the patch to match) --"
    sed -n '/EL2-only (VHE mode)/,/PMC FIQ/p' drivers/irqchip/irq-apple-aic.c
    exit 1
fi
echo "== skip T6040 locked vGIC maintenance register write =="
if ! sed -n '/static int aic_init_cpu/,/PMC FIQ/p' \
       drivers/irqchip/irq-apple-aic.c | \
       grep -q '^[[:space:]]*sysreg_clear_set_s(SYS_ICH_HCR_EL2'; then
    echo "t6040-aic-hcr-debug.patch already applied"
elif git apply --check /out/t6040-aic-hcr-debug.patch 2>/dev/null; then
    git apply /out/t6040-aic-hcr-debug.patch
    echo "t6040-aic-hcr-debug.patch applied OK"
else
    echo "ERROR: t6040-aic-hcr-debug.patch does not apply cleanly:"
    git apply --check /out/t6040-aic-hcr-debug.patch || true
    exit 1
fi

echo "-- verify the two traps are gone from aic_init_cpu --"
if sed -n '/static int aic_init_cpu/,/PMC FIQ/p' drivers/irqchip/irq-apple-aic.c | grep -qE "^\s*sysreg_clear_set_s\(SYS_(IMP_APL_VM_TMR_FIQ_ENA|ICH_HCR)_EL2"; then
    echo "ERROR: a locked-sysreg write is still active in aic_init_cpu!"
    exit 1
else
    echo "aic_init_cpu locked-sysreg writes disabled OK"
fi

if [ "${USB_HOST:-0}" = "1" ]; then
    echo "== apply dwc3-apple force-host-mode patch (USB2 external-root, ticket 032) =="
    if git apply --check /out/t6040-dwc3-apple-force-host.patch 2>/dev/null; then
        git apply /out/t6040-dwc3-apple-force-host.patch
        echo "t6040-dwc3-apple-force-host.patch applied OK"
    elif git apply -R --check /out/t6040-dwc3-apple-force-host.patch 2>/dev/null; then
        echo "t6040-dwc3-apple-force-host.patch already applied"
    else
        echo "ERROR: t6040-dwc3-apple-force-host.patch does not apply cleanly:"
        git apply --check /out/t6040-dwc3-apple-force-host.patch || true
        exit 1
    fi
fi

# A reused build tree can retain the old MTP IRQ-order diagnostics even though
# the source tree and current patch set are clean. Remove that known residue
# deterministically instead of allowing unconditional mailbox logs into images.
if grep -qR 'MTPDBG' drivers/soc/apple/mailbox.c drivers/soc/apple/rtkit.c; then
    echo "== remove stale MTPDBG instrumentation =="
    if git apply --check /out/t6040-remove-mtpdbg.patch 2>/dev/null; then
        git apply /out/t6040-remove-mtpdbg.patch
        echo "t6040-remove-mtpdbg.patch applied OK"
    else
        echo "ERROR: stale MTPDBG code does not match the known removal patch:"
        git apply --check /out/t6040-remove-mtpdbg.patch || true
        exit 1
    fi
fi

echo "== apply T8140 ANS storage bindings =="
if grep -q 'apple,t8140-nvme-ans2' \
    Documentation/devicetree/bindings/nvme/apple,nvme-ans.yaml; then
    echo "t8140-ans-bindings.patch already applied"
elif git apply --check /out/t8140-ans-bindings.patch 2>/dev/null; then
    git apply /out/t8140-ans-bindings.patch
    echo "t8140-ans-bindings.patch applied OK"
else
    echo "ERROR: t8140-ans-bindings.patch does not apply cleanly:"
    git apply --check /out/t8140-ans-bindings.patch || true
    exit 1
fi

echo "== apply T8140 CoastGuard SART power binding =="
if grep -q 'const: power' \
    Documentation/devicetree/bindings/iommu/apple,sart.yaml; then
    echo "t8140-sart-power-bindings.patch already applied"
elif git apply --check /out/t8140-sart-power-bindings.patch 2>/dev/null; then
    git apply /out/t8140-sart-power-bindings.patch
    echo "t8140-sart-power-bindings.patch applied OK"
else
    echo "ERROR: t8140-sart-power-bindings.patch does not apply cleanly:"
    git apply --check /out/t8140-sart-power-bindings.patch || true
    exit 1
fi

echo "== apply T8140 CoastGuard SART power management =="
if grep -q 'CoastGuard SART power-control' drivers/soc/apple/sart.c; then
    echo "t8140-sart-power-managed.patch already applied"
elif git apply --check /out/t8140-sart-power-managed.patch 2>/dev/null; then
    git apply /out/t8140-sart-power-managed.patch
    echo "t8140-sart-power-managed.patch applied OK"
else
    echo "ERROR: t8140-sart-power-managed.patch does not apply cleanly:"
    git apply --check /out/t8140-sart-power-managed.patch || true
    exit 1
fi

# The historical probe-isolation images predate the deferred-scan fix and are
# intentionally built from the original power-management patch.
if { [ "${SART_HANDSHAKE_ONLY:-0}" = "1" ] ||
     [ "${SART_DEFERRED_PROBE:-0}" = "1" ]; } &&
   grep -q 'entries_scanned' drivers/soc/apple/sart.c; then
    echo "== remove T8140 deferred-scan fix for probe diagnostic =="
    git apply -R /out/t8140-sart-defer-scan.patch
fi

# Bring-up-only isolation: perform the exact CoastGuard activate/deactivate
# handshake during probe, but do not touch the SART entry register file.  Keep
# this reversible because the container build tree is intentionally reused.
if [ "${SART_HANDSHAKE_ONLY:-0}" = "1" ]; then
    [ "${NVME:-0}" = "1" ] || {
        echo "ERROR: SART_HANDSHAKE_ONLY=1 requires NVME=1"
        exit 1
    }
    echo "== apply T8140 SART handshake-only diagnostic =="
    if grep -q 'handshake-only diagnostic' drivers/soc/apple/sart.c; then
        echo "t8140-sart-handshake-only-debug.patch already applied"
    elif git apply --check /out/t8140-sart-handshake-only-debug.patch 2>/dev/null; then
        git apply /out/t8140-sart-handshake-only-debug.patch
        echo "t8140-sart-handshake-only-debug.patch applied OK"
    else
        echo "ERROR: t8140-sart-handshake-only-debug.patch does not apply cleanly:"
        git apply --check /out/t8140-sart-handshake-only-debug.patch || true
        exit 1
    fi
elif grep -q 'handshake-only diagnostic' drivers/soc/apple/sart.c; then
    echo "== remove T8140 SART handshake-only diagnostic =="
    git apply -R /out/t8140-sart-handshake-only-debug.patch
fi

if [ "${SART_DEFERRED_PROBE:-0}" = "1" ]; then
    [ "${NVME:-0}" = "1" ] || {
        echo "ERROR: SART_DEFERRED_PROBE=1 requires NVME=1"
        exit 1
    }
    [ "${SART_HANDSHAKE_ONLY:-0}" != "1" ] || {
        echo "ERROR: SART diagnostic modes are mutually exclusive"
        exit 1
    }
    echo "== apply T8140 SART zero-MMIO probe diagnostic =="
    if grep -q 'deferred-probe diagnostic' drivers/soc/apple/sart.c; then
        echo "t8140-sart-deferred-probe-debug.patch already applied"
    elif git apply --check /out/t8140-sart-deferred-probe-debug.patch 2>/dev/null; then
        git apply /out/t8140-sart-deferred-probe-debug.patch
        echo "t8140-sart-deferred-probe-debug.patch applied OK"
    else
        echo "ERROR: t8140-sart-deferred-probe-debug.patch does not apply cleanly:"
        git apply --check /out/t8140-sart-deferred-probe-debug.patch || true
        exit 1
    fi
elif grep -q 'deferred-probe diagnostic' drivers/soc/apple/sart.c; then
    echo "== remove T8140 SART zero-MMIO probe diagnostic =="
    git apply -R /out/t8140-sart-deferred-probe-debug.patch
fi

if [ "${SART_HANDSHAKE_ONLY:-0}" != "1" ] &&
   [ "${SART_DEFERRED_PROBE:-0}" != "1" ]; then
    echo "== defer T8140 CoastGuard access until its first client operation =="
    if grep -q 'entries_scanned' drivers/soc/apple/sart.c; then
        echo "t8140-sart-defer-scan.patch already applied"
    elif git apply --check /out/t8140-sart-defer-scan.patch 2>/dev/null; then
        git apply /out/t8140-sart-defer-scan.patch
        echo "t8140-sart-defer-scan.patch applied OK"
    else
        echo "ERROR: t8140-sart-defer-scan.patch does not apply cleanly:"
        git apply --check /out/t8140-sart-defer-scan.patch || true
        exit 1
    fi
fi

if [ "${NVME_INIT_TRACE:-0}" != "1" ] &&
   grep -q 'before linear queue and NVMMU setup' \
       drivers/nvme/host/apple.c; then
    echo "== remove post-ANS Apple NVMe setup trace =="
    git apply -R /out/t6040-nvme-init-trace-debug.patch
fi

if [ "${NVME_FORCE_CONTINUE:-0}" != "1" ] &&
   grep -q 'continuing to controller reset work' \
       drivers/nvme/host/apple.c; then
    echo "== remove Apple NVMe force-active continuation diagnostic =="
    git apply -R /out/t6040-nvme-force-continue-debug.patch
fi

if [ "${NVME_ANS_READ:-0}" != "1" ] &&
   [ "${NVME_FORCE_CONTINUE:-0}" != "1" ] &&
   grep -q 'isolated ANS CPU control read returned' \
       drivers/nvme/host/apple.c; then
    echo "== remove isolated Apple ANS-read diagnostic =="
    git apply -R /out/t6040-nvme-ans-read-debug.patch
fi

if [ "${PMGR_FORCE_ACTIVE:-0}" != "1" ] &&
   grep -q 'PMGR force-active verified; stopping before ANS MMIO' \
       drivers/nvme/host/apple.c; then
    echo "== remove Apple PMGR force-active diagnostic =="
    git apply -R /out/t6040-pmgr-force-active-debug.patch
fi

if [ "${NVME_PMGR_SNAPSHOT:-0}" != "1" ] &&
   grep -q 'raw PMGR snapshot complete; stopping before ANS MMIO' \
       drivers/nvme/host/apple.c; then
    echo "== remove Apple NVMe raw-PMGR snapshot diagnostic =="
    git apply -R /out/t6040-nvme-pmgr-snapshot-debug.patch
fi

if [ "${SART_TRACE:-0}" = "1" ]; then
    echo "== apply T8140 SART transition trace diagnostic =="
    if grep -q 'trace: CoastGuard activate begin' drivers/soc/apple/sart.c; then
        echo "t8140-sart-trace-debug.patch already applied"
    elif git apply --check /out/t8140-sart-trace-debug.patch 2>/dev/null; then
        git apply /out/t8140-sart-trace-debug.patch
        echo "t8140-sart-trace-debug.patch applied OK"
    else
        echo "ERROR: t8140-sart-trace-debug.patch does not apply cleanly:"
        git apply --check /out/t8140-sart-trace-debug.patch || true
        exit 1
    fi
    echo "== apply Apple NVMe first-probe phase trace diagnostic =="
    if grep -Fq 'apple_nvme_trace(&pdev->dev, "platform probe entered")' \
        drivers/nvme/host/apple.c; then
        echo "t6040-nvme-trace-debug.patch already applied"
    elif git apply --check /out/t6040-nvme-trace-debug.patch 2>/dev/null; then
        git apply /out/t6040-nvme-trace-debug.patch
        echo "t6040-nvme-trace-debug.patch applied OK"
    else
        echo "ERROR: t6040-nvme-trace-debug.patch does not apply cleanly:"
        git apply --check /out/t6040-nvme-trace-debug.patch || true
        exit 1
    fi
else
    if grep -q 'trace: CoastGuard activate begin' drivers/soc/apple/sart.c; then
        echo "== remove T8140 SART transition trace diagnostic =="
        git apply -R /out/t8140-sart-trace-debug.patch
    fi
    if grep -Fq 'apple_nvme_trace(&pdev->dev, "platform probe entered")' \
        drivers/nvme/host/apple.c; then
        echo "== remove Apple NVMe first-probe phase trace diagnostic =="
        git apply -R /out/t6040-nvme-trace-debug.patch
    fi
fi

if [ "${NVME_PMGR_SNAPSHOT:-0}" = "1" ]; then
    [ "${NVME:-0}" = "1" ] || {
        echo "ERROR: NVME_PMGR_SNAPSHOT=1 requires NVME=1"
        exit 1
    }
    [ "${NVME_MODE:-builtin}" = "staged" ] || {
        echo "ERROR: NVME_PMGR_SNAPSHOT=1 requires NVME_MODE=staged"
        exit 1
    }
    [ "${SART_TRACE:-0}" = "1" ] || {
        echo "ERROR: NVME_PMGR_SNAPSHOT=1 requires SART_TRACE=1"
        exit 1
    }
    echo "== apply Apple NVMe raw-PMGR snapshot diagnostic =="
    if grep -q 'raw PMGR snapshot complete; stopping before ANS MMIO' \
        drivers/nvme/host/apple.c; then
        echo "t6040-nvme-pmgr-snapshot-debug.patch already applied"
    elif git apply --check /out/t6040-nvme-pmgr-snapshot-debug.patch 2>/dev/null; then
        git apply /out/t6040-nvme-pmgr-snapshot-debug.patch
        echo "t6040-nvme-pmgr-snapshot-debug.patch applied OK"
    else
        echo "ERROR: t6040-nvme-pmgr-snapshot-debug.patch does not apply cleanly:"
        git apply --check /out/t6040-nvme-pmgr-snapshot-debug.patch || true
        exit 1
    fi
fi

echo "== apply T6041 PMGR bindings =="
if grep -q 'apple,t6041-pmgr' \
    Documentation/devicetree/bindings/arm/apple/apple,pmgr.yaml; then
    echo "t6040-pmgr-t6041-bindings.patch already applied"
elif git apply --check /out/t6040-pmgr-t6041-bindings.patch 2>/dev/null; then
    git apply /out/t6040-pmgr-t6041-bindings.patch
    echo "t6040-pmgr-t6041-bindings.patch applied OK"
else
    echo "ERROR: t6040-pmgr-t6041-bindings.patch does not apply cleanly:"
    git apply --check /out/t6040-pmgr-t6041-bindings.patch || true
    exit 1
fi

echo "== apply T6041 PMGR raw-boot quirks =="
if grep -q 'T6041 raw boot firmware locks auto-PM' \
    drivers/pmdomain/apple/pmgr-pwrstate.c; then
    echo "t6040-pmgr-t6041-quirks.patch already applied"
elif git apply --check /out/t6040-pmgr-t6041-quirks.patch 2>/dev/null; then
    git apply /out/t6040-pmgr-t6041-quirks.patch
    echo "t6040-pmgr-t6041-quirks.patch applied OK"
else
    echo "ERROR: t6040-pmgr-t6041-quirks.patch does not apply cleanly:"
    git apply --check /out/t6040-pmgr-t6041-quirks.patch || true
    exit 1
fi

if [ "${NVME:-0}" = "1" ]; then
    echo "== keep T6041 ANS fully active until first access =="
    if grep -q '!strcmp(name, "ans")' drivers/pmdomain/apple/pmgr-pwrstate.c; then
        echo "t6040-pmgr-ans-no-auto.patch already applied"
    elif git apply --check /out/t6040-pmgr-ans-no-auto.patch 2>/dev/null; then
        git apply /out/t6040-pmgr-ans-no-auto.patch
        echo "t6040-pmgr-ans-no-auto.patch applied OK"
    else
        echo "ERROR: t6040-pmgr-ans-no-auto.patch does not apply cleanly:"
        git apply --check /out/t6040-pmgr-ans-no-auto.patch || true
        exit 1
    fi
elif grep -q '!strcmp(name, "ans")' drivers/pmdomain/apple/pmgr-pwrstate.c; then
    echo "== remove T6041 ANS auto-PM exception =="
    git apply -R /out/t6040-pmgr-ans-no-auto.patch
fi

if [ "${PMGR_FORCE_ACTIVE:-0}" = "1" ]; then
    [ "${NVME_PMGR_SNAPSHOT:-0}" = "1" ] || {
        echo "ERROR: PMGR_FORCE_ACTIVE=1 requires NVME_PMGR_SNAPSHOT=1"
        exit 1
    }
    echo "== apply Apple PMGR force-active diagnostic =="
    if grep -q 'PMGR force-active verified; stopping before ANS MMIO' \
        drivers/nvme/host/apple.c; then
        echo "t6040-pmgr-force-active-debug.patch already applied"
    elif git apply --check /out/t6040-pmgr-force-active-debug.patch 2>/dev/null; then
        git apply /out/t6040-pmgr-force-active-debug.patch
        echo "t6040-pmgr-force-active-debug.patch applied OK"
    else
        echo "ERROR: t6040-pmgr-force-active-debug.patch does not apply cleanly:"
        git apply --check /out/t6040-pmgr-force-active-debug.patch || true
        exit 1
    fi
fi

if [ "${NVME_ANS_READ:-0}" = "1" ]; then
    [ "${PMGR_FORCE_ACTIVE:-0}" = "1" ] || {
        echo "ERROR: NVME_ANS_READ=1 requires PMGR_FORCE_ACTIVE=1"
        exit 1
    }
    echo "== apply isolated Apple ANS-read diagnostic =="
    if grep -q 'isolated ANS CPU control read returned' \
        drivers/nvme/host/apple.c; then
        echo "t6040-nvme-ans-read-debug.patch already applied"
    elif git apply --check /out/t6040-nvme-ans-read-debug.patch 2>/dev/null; then
        git apply /out/t6040-nvme-ans-read-debug.patch
        echo "t6040-nvme-ans-read-debug.patch applied OK"
    else
        echo "ERROR: t6040-nvme-ans-read-debug.patch does not apply cleanly:"
        git apply --check /out/t6040-nvme-ans-read-debug.patch || true
        exit 1
    fi
fi

if [ "${NVME_FORCE_CONTINUE:-0}" = "1" ]; then
    [ "${NVME_ANS_READ:-0}" = "1" ] || {
        echo "ERROR: NVME_FORCE_CONTINUE=1 requires NVME_ANS_READ=1"
        exit 1
    }
    echo "== apply Apple NVMe force-active continuation diagnostic =="
    if grep -q 'continuing to controller reset work' \
        drivers/nvme/host/apple.c; then
        echo "t6040-nvme-force-continue-debug.patch already applied"
    elif git apply --check /out/t6040-nvme-force-continue-debug.patch 2>/dev/null; then
        git apply /out/t6040-nvme-force-continue-debug.patch
        echo "t6040-nvme-force-continue-debug.patch applied OK"
    else
        echo "ERROR: t6040-nvme-force-continue-debug.patch does not apply cleanly:"
        git apply --check /out/t6040-nvme-force-continue-debug.patch || true
        exit 1
    fi
fi

if [ "${NVME_INIT_TRACE:-0}" = "1" ]; then
    [ "${NVME_FORCE_CONTINUE:-0}" = "1" ] || {
        echo "ERROR: NVME_INIT_TRACE=1 requires NVME_FORCE_CONTINUE=1"
        exit 1
    }
    echo "== apply post-ANS Apple NVMe setup trace =="
    if grep -q 'before linear queue and NVMMU setup' \
        drivers/nvme/host/apple.c; then
        echo "t6040-nvme-init-trace-debug.patch already applied"
    elif git apply --check /out/t6040-nvme-init-trace-debug.patch 2>/dev/null; then
        git apply /out/t6040-nvme-init-trace-debug.patch
        echo "t6040-nvme-init-trace-debug.patch applied OK"
    else
        echo "ERROR: t6040-nvme-init-trace-debug.patch does not apply cleanly:"
        git apply --check /out/t6040-nvme-init-trace-debug.patch || true
        exit 1
    fi
fi

if [ "${NVME_SPTM_TRACE:-0}" = "1" ] &&
   [ "${NVME_REGISTER_TRACE:-0}" != "1" ]; then
    echo "ERROR: NVME_SPTM_TRACE=1 requires NVME_REGISTER_TRACE=1"
    exit 1
fi
if [ "${NVME_SPTM_TRACE:-0}" != "1" ] &&
   grep -q 'before protected admin queue setup' drivers/nvme/host/apple.c; then
    echo "== remove protected T8140 queue setup diagnostic =="
    git apply -R /out/t6040-nvme-sptm-debug.patch
fi

if [ "${NVME_REGISTER_TRACE:-0}" = "1" ]; then
    [ "${NVME_INIT_TRACE:-0}" = "1" ] || {
        echo "ERROR: NVME_REGISTER_TRACE=1 requires NVME_INIT_TRACE=1"
        exit 1
    }
    echo "== apply individual post-ANS register trace =="
    if grep -q 'preserving firmware-owned linear queue' drivers/nvme/host/apple.c; then
        echo "t6040-nvme-register-trace-debug.patch already applied"
    elif git apply --check /out/t6040-nvme-register-trace-debug.patch 2>/dev/null; then
        git apply /out/t6040-nvme-register-trace-debug.patch
        echo "t6040-nvme-register-trace-debug.patch applied OK"
    else
        echo "ERROR: t6040-nvme-register-trace-debug.patch does not apply cleanly:"
        git apply --check /out/t6040-nvme-register-trace-debug.patch || true
        exit 1
    fi
elif grep -q 'preserving firmware-owned linear queue' drivers/nvme/host/apple.c; then
    echo "== remove individual post-ANS register trace =="
    git apply -R /out/t6040-nvme-register-trace-debug.patch
fi

if [ "${NVME_SPTM_TRACE:-0}" = "1" ]; then
    echo "== apply protected T8140 queue setup diagnostic =="
    if grep -q 'before protected admin queue setup' drivers/nvme/host/apple.c; then
        echo "t6040-nvme-sptm-debug.patch already applied"
    elif git apply --check /out/t6040-nvme-sptm-debug.patch 2>/dev/null; then
        git apply /out/t6040-nvme-sptm-debug.patch
        echo "t6040-nvme-sptm-debug.patch applied OK"
    else
        echo "ERROR: t6040-nvme-sptm-debug.patch does not apply cleanly:"
        git apply --check /out/t6040-nvme-sptm-debug.patch || true
        exit 1
    fi
fi

if [ "${PMGR_FUNCTIONAL:-0}" = "1" ]; then
    echo "== apply minimal T6040 PMGR functional policy =="
    if grep -q 'skipping unsupported auto-enable' drivers/pmdomain/apple/pmgr-pwrstate.c; then
        echo "t6040-pmgr-functional.patch already applied"
    elif git apply --check /out/t6040-pmgr-functional.patch 2>/dev/null; then
        git apply /out/t6040-pmgr-functional.patch
        echo "t6040-pmgr-functional.patch applied OK"
    else
        echo "ERROR: t6040-pmgr-functional.patch does not apply cleanly:"
        git apply --check /out/t6040-pmgr-functional.patch || true
        exit 1
    fi
fi

if [ "${DOCKCHANNEL:-0}" = "1" ]; then
    echo "== import local DockChannel mailbox + HID transport series =="
    if [ -f drivers/hid/apple-dockchannel-hid/apple_dockchannel_hid.c ]; then
        echo "DockChannel HID series already applied"
    else
        for commit in \
            d2acb86f70a252cc458101d855e6e4c950031174 \
            f2b7718fd46c34b8c500ae77bdb7129de3494105 \
            c4a0e3d1b55d2ceca114681c1bae7aeb9caf06ea \
            356985c33ceb197790012a2362542c2b62baea0a; do
            git show --format=email --no-ext-diff "$commit" | git apply
        done
        # The branch tip corrects the byte FIFO TX accessor to a 32-bit write.
        git show --format=email --no-ext-diff ba89d30070d42082a5eca95419e72f1e132b0893 \
            -- drivers/mailbox/apple-dockchannel.c | git apply
        echo "DockChannel HID series applied OK"
    fi
    # DockChannel serial TTY (/dev/ttydcN) — carries the AP dockchannel-uart
    # byte stream; with a DebugUSB/KIS session active the host reads it via
    # kisd uart channel 0. Separate commit later in origin/dockchannel.
    if [ -f drivers/tty/apple_dockchannel_tty.c ]; then
        echo "DockChannel serial TTY already applied"
    else
        git show --format=email --no-ext-diff \
            b8dcbdcb9cbf1d18be7cf30c1f839a204b0aec33 | git apply
        echo "DockChannel serial TTY applied OK"
    fi
    # Local fallback plus per-instance IRQ masks. MTP uses RX BIT(3), while the
    # UART FIFO uses RX BIT(1). The atomic transmit patch is based on this
    # version, so the fallback must be explicit before the nbcon pair.
    if grep -q 'apple,poll-mode' drivers/mailbox/apple-dockchannel.c; then
        echo "t6040-dockchannel-poll.patch already applied"
    elif git apply --check /out/t6040-dockchannel-poll.patch 2>/dev/null; then
        git apply /out/t6040-dockchannel-poll.patch
        echo "t6040-dockchannel-poll.patch applied OK"
    else
        echo "ERROR: t6040-dockchannel-poll.patch does not apply cleanly:"
        git apply --check /out/t6040-dockchannel-poll.patch || true
        exit 1
    fi
    if [ "${DOCKCHANNEL_NBCON:-0}" = "1" ]; then
        echo "== apply bounded atomic DockChannel transmit =="
        if grep -q 'apple_dockchannel_send_atomic' \
                drivers/mailbox/apple-dockchannel.c; then
            echo "t6040-dockchannel-atomic-tx.patch already applied"
        elif git apply --check \
                /out/t6040-dockchannel-atomic-tx.patch 2>/dev/null; then
            git apply /out/t6040-dockchannel-atomic-tx.patch
            echo "t6040-dockchannel-atomic-tx.patch applied OK"
        else
            echo "ERROR: t6040-dockchannel-atomic-tx.patch does not apply:"
            git apply --check /out/t6040-dockchannel-atomic-tx.patch || true
            exit 1
        fi
        echo "== apply DockChannel nbcon diagnostic =="
        if grep -q 'CON_PRINTBUFFER | CON_NBCON' \
                drivers/tty/apple_dockchannel_tty.c; then
            echo "t6040-dockchannel-nbcon.patch already applied"
        elif git apply --check \
                /out/t6040-dockchannel-nbcon.patch 2>/dev/null; then
            git apply /out/t6040-dockchannel-nbcon.patch
            echo "t6040-dockchannel-nbcon.patch applied OK"
        else
            echo "ERROR: t6040-dockchannel-nbcon.patch does not apply:"
            git apply --check /out/t6040-dockchannel-nbcon.patch || true
            exit 1
        fi
    else
        if grep -q 'CON_PRINTBUFFER | CON_NBCON' \
                drivers/tty/apple_dockchannel_tty.c &&
                git apply -R --check \
                    /out/t6040-dockchannel-nbcon.patch 2>/dev/null; then
            git apply -R /out/t6040-dockchannel-nbcon.patch
            echo "t6040-dockchannel-nbcon.patch removed"
        fi
        if grep -q 'apple_dockchannel_send_atomic' \
                drivers/mailbox/apple-dockchannel.c &&
                git apply -R --check \
                    /out/t6040-dockchannel-atomic-tx.patch 2>/dev/null; then
            git apply -R /out/t6040-dockchannel-atomic-tx.patch
            echo "t6040-dockchannel-atomic-tx.patch removed"
        fi
    fi
    if [ "${DOCKCHANNEL_EARLYCON:-0}" = "1" ]; then
        echo "== apply bounded DockChannel early console diagnostic =="
        if grep -q 'apple_dctty_early_setup' \
                drivers/tty/apple_dockchannel_tty.c; then
            echo "t6040-dockchannel-earlycon-debug.patch already applied"
        elif git apply --check \
                /out/t6040-dockchannel-earlycon-debug.patch 2>/dev/null; then
            git apply /out/t6040-dockchannel-earlycon-debug.patch
            echo "t6040-dockchannel-earlycon-debug.patch applied OK"
        else
            echo "ERROR: t6040-dockchannel-earlycon-debug.patch does not apply:"
            git apply --check \
                /out/t6040-dockchannel-earlycon-debug.patch || true
            exit 1
        fi
    elif grep -q 'apple_dctty_early_setup' \
            drivers/tty/apple_dockchannel_tty.c &&
            git apply -R --check \
                /out/t6040-dockchannel-earlycon-debug.patch 2>/dev/null; then
        git apply -R /out/t6040-dockchannel-earlycon-debug.patch
        echo "t6040-dockchannel-earlycon-debug.patch removed"
    fi
    if [ "${HID_RX_REARM:-0}" = "1" ]; then
        if git apply --check /out/t6040-dockchannel-rx-rearm.patch 2>/dev/null; then
            git apply /out/t6040-dockchannel-rx-rearm.patch
            echo "t6040-dockchannel-rx-rearm.patch applied OK"
        elif git apply -R --check /out/t6040-dockchannel-rx-rearm.patch 2>/dev/null; then
            echo "t6040-dockchannel-rx-rearm.patch already applied"
        else
            echo "ERROR: t6040-dockchannel-rx-rearm.patch does not apply cleanly:"
            git apply --check /out/t6040-dockchannel-rx-rearm.patch || true
            exit 1
        fi
    fi
    if [ "${HID_TYPE_FIX:-0}" = "1" ]; then
        # Set hid->type so the rebased BUS_HOST hid-apple driver accepts the
        # internal keyboard. Ticket 078 registered event0 with this source
        # change; keep it gated so unrelated historical candidates are stable.
        if grep -q 'hid->type = HID_TYPE_SPI_KEYBOARD' \
            drivers/hid/apple-dockchannel-hid/apple_dockchannel_hid.c; then
            echo "t6040-dockchannel-hid-type.patch already applied"
        elif git apply --check \
                /out/t6040-dockchannel-hid-type.patch 2>/dev/null; then
            git apply /out/t6040-dockchannel-hid-type.patch
            echo "t6040-dockchannel-hid-type.patch applied OK"
        else
            echo "ERROR: t6040-dockchannel-hid-type.patch does not apply cleanly:"
            git apply --check /out/t6040-dockchannel-hid-type.patch || true
            exit 1
        fi
    elif grep -q 'hid->type = HID_TYPE_SPI_KEYBOARD' \
            drivers/hid/apple-dockchannel-hid/apple_dockchannel_hid.c &&
            git apply -R --check \
                /out/t6040-dockchannel-hid-type.patch 2>/dev/null; then
        # Reused case-sensitive build directories retain applied patches.
        # Restore the baseline when this candidate is not explicitly selected.
        git apply -R /out/t6040-dockchannel-hid-type.patch
        echo "t6040-dockchannel-hid-type.patch removed (HID_TYPE_FIX=0)"
    fi
    if [ "${DOCKCHANNEL_IRQ_TEST:-0}" = "1" ]; then
        echo "== apply bounded DockChannel IRQ diagnostic guard =="
        if grep -q 'IRQ storm guard tripped' drivers/mailbox/apple-dockchannel.c; then
            echo "t6040-dockchannel-irq-guard-debug.patch already applied"
        elif git apply --check /out/t6040-dockchannel-irq-guard-debug.patch 2>/dev/null; then
            git apply /out/t6040-dockchannel-irq-guard-debug.patch
            echo "t6040-dockchannel-irq-guard-debug.patch applied OK"
        else
            echo "ERROR: t6040-dockchannel-irq-guard-debug.patch does not apply cleanly:"
            git apply --check /out/t6040-dockchannel-irq-guard-debug.patch || true
            exit 1
        fi
    fi
    if [ "${DOCKCHANNEL_IRQ_TX_POLL_TEST:-0}" = "1" ]; then
        echo "== apply DockChannel RX-IRQ/TX-poll diagnostic split =="
        if grep -q 'apple,tx-poll-mode' drivers/mailbox/apple-dockchannel.c; then
            echo "t6040-dockchannel-tx-poll-debug.patch already applied"
        elif git apply --check /out/t6040-dockchannel-tx-poll-debug.patch 2>/dev/null; then
            git apply /out/t6040-dockchannel-tx-poll-debug.patch
            echo "t6040-dockchannel-tx-poll-debug.patch applied OK"
        else
            echo "ERROR: t6040-dockchannel-tx-poll-debug.patch does not apply cleanly:"
            git apply --check /out/t6040-dockchannel-tx-poll-debug.patch || true
            exit 1
        fi
        echo "== apply bounded DockChannel FIFO/IRQ telemetry =="
        if grep -q 'apple,irq-telemetry' drivers/mailbox/apple-dockchannel.c; then
            echo "t6040-dockchannel-fifo-telemetry-debug.patch already applied"
        elif git apply --check /out/t6040-dockchannel-fifo-telemetry-debug.patch 2>/dev/null; then
            git apply /out/t6040-dockchannel-fifo-telemetry-debug.patch
            echo "t6040-dockchannel-fifo-telemetry-debug.patch applied OK"
        else
            echo "ERROR: t6040-dockchannel-fifo-telemetry-debug.patch does not apply cleanly:"
            git apply --check /out/t6040-dockchannel-fifo-telemetry-debug.patch || true
            exit 1
        fi
    elif grep -q 'apple,tx-poll-mode' drivers/mailbox/apple-dockchannel.c; then
        echo "== remove DockChannel RX-IRQ/TX-poll diagnostic split =="
        if grep -q 'apple,irq-telemetry' drivers/mailbox/apple-dockchannel.c; then
            git apply -R /out/t6040-dockchannel-fifo-telemetry-debug.patch
        fi
        git apply -R /out/t6040-dockchannel-tx-poll-debug.patch
    fi
    # Local fix: add the missing hid_ll_driver .stop (NULL-deref oops on t6040,
    # see ~/Code/wallace/t6040-dockchannel-fixes.patch; copy it to /out first).
    if grep -q 'dchid_stop' \
        drivers/hid/apple-dockchannel-hid/apple_dockchannel_hid.c; then
        echo "t6040-dockchannel-fixes.patch already applied"
    elif git apply --check /out/t6040-dockchannel-fixes.patch 2>/dev/null; then
        git apply /out/t6040-dockchannel-fixes.patch
        echo "t6040-dockchannel-fixes.patch applied OK"
    else
        echo "ERROR: t6040-dockchannel-fixes.patch does not apply cleanly:"
        git apply --check /out/t6040-dockchannel-fixes.patch || true
        exit 1
    fi
    # The upstream-oriented transport is keyboard-only. Restore the bounded
    # HIDF firmware upload used by multi-touch; the board DT supplies the
    # paired, extracted firmware filename.
    if grep -q 'DCHID_FW_MAGIC' \
        drivers/hid/apple-dockchannel-hid/apple_dockchannel_hid.c; then
        echo "t6040-dockchannel-trackpad-fw.patch already applied"
    elif git apply --check /out/t6040-dockchannel-trackpad-fw.patch 2>/dev/null; then
        git apply /out/t6040-dockchannel-trackpad-fw.patch
        echo "t6040-dockchannel-trackpad-fw.patch applied OK"
    else
        echo "ERROR: t6040-dockchannel-trackpad-fw.patch does not apply cleanly:"
        git apply --check /out/t6040-dockchannel-trackpad-fw.patch || true
        exit 1
    fi
    if [ "${HID_STATE_TRACE:-0}" = "1" ]; then
        if grep -q 'trace_irq_calls' drivers/mailbox/apple-dockchannel.c; then
            echo "t6040-dockchannel-hid-state-trace.patch already applied"
        elif git apply --check \
                /out/t6040-dockchannel-hid-state-trace.patch 2>/dev/null; then
            git apply /out/t6040-dockchannel-hid-state-trace.patch
            echo "t6040-dockchannel-hid-state-trace.patch applied OK"
        else
            echo "ERROR: t6040-dockchannel-hid-state-trace.patch does not apply cleanly:"
            git apply --check \
                /out/t6040-dockchannel-hid-state-trace.patch || true
            exit 1
        fi
    fi
fi

echo "== verify netfilter case-collision is healed in the clone =="
git status --short include/uapi/linux/netfilter/xt_mark.h || true

echo "== config (arm64 defconfig enables CONFIG_ARCH_APPLE) =="
make ARCH=arm64 defconfig >/dev/null
grep -q "CONFIG_ARCH_APPLE=y" .config && echo "ARCH_APPLE=y OK" || echo "WARN: ARCH_APPLE not set"

echo "== force on-screen framebuffer console (the only working kernel console on"
echo "   M4 raw-boot: no serial earlycon, no hv relay). Read output on the laptop"
echo "   display. Mirrors mischa85's t6041 baremetal boot-to-userspace recipe. =="
# simpledrm binds /chosen/framebuffer (m1n1 fills it in), FBDEV_EMULATION gives it
# an fbdev, and FRAMEBUFFER_CONSOLE (fbcon) renders printk onto that fbdev. Without
# all three you get the m1n1 logo and no text (defconfig ships DRM=m, simpledrm off).
# ARM64_SME must be OFF on M4 (chaos_princess/StanfordAppliedCyber: SME breaks M4 boot).
./scripts/config --file .config \
    -e DRM -e DRM_SIMPLEDRM -e DRM_FBDEV_EMULATION \
    -e FB -e VT -e VT_CONSOLE \
    -e FRAMEBUFFER_CONSOLE -e FRAMEBUFFER_CONSOLE_DETECT_PRIMARY \
    -e LOGO -e WATCHDOG -e APPLE_WATCHDOG \
    -e FONTS \
    -d ARM64_SME
# Terminus 16x32: double-size console text for the 3024x1964 panel (boot with
# fbcon=font:TER16x32). scripts/config uppercases symbol names, so sed directly.
if grep -q "CONFIG_FONT_TER16x32" .config; then
    sed -i 's|# CONFIG_FONT_TER16x32 is not set|CONFIG_FONT_TER16x32=y|' .config
else
    echo "CONFIG_FONT_TER16x32=y" >> .config
fi
if [ "${DOCKCHANNEL:-0}" = "1" ]; then
    ./scripts/config --file .config \
        -e APPLE_MAILBOX -e APPLE_RTKIT -e APPLE_DART \
        -e HID -e HID_APPLE -e APPLE_DOCKCHANNEL \
        -e APPLE_DOCKCHANNEL_HID -e APPLE_DOCKCHANNEL_TTY
fi
if [ "${TRACKPAD_MOTION:-0}" = "1" ]; then
    # The bounded RAM image has no module-loading path. Multi-touch must be
    # built in so opening the event node can invoke the paired volatile HIDF
    # upload path; ticket 004's first exact candidate incorrectly left this m.
    ./scripts/config --file .config -e HID_MULTITOUCH
fi
if [ "${MACSMC:-0}" = "1" ]; then
    # Feature kernel (tickets 165/167 + USB-tether ethernet). The base .config
    # already carries MFD_MACSMC=m and USB_USBNET=m, but the bounded RAM image
    # has no module loader, so everything must be BUILTIN (=y).
    echo "== MACSMC: battery/thermals + usbnet + USB-gadget ethernet (builtin) =="
    # SMC: battery, charge state, temperatures (read-only telemetry).
    ./scripts/config --file .config \
        -e MFD_MACSMC -e MACSMC_POWER -e SENSORS_MACSMC_HWMON \
        -e HWMON -e POWER_SUPPLY -e RTC_DRV_MACSMC -e RTC_CLASS
    # USB storage and ethernet dongles on a host port (read/write and cheap
    # networking once the right-port Type-C/VBUS path works).  Defconfig
    # supplies USB_STORAGE but not UAS, so name both explicitly: ticket 167's
    # feature promise must survive config drift.
    ./scripts/config --file .config \
        -e SCSI -e BLK_DEV_SD -e USB_STORAGE -e USB_UAS \
        -e USB_NET_DRIVERS -e USB_USBNET -e USB_NET_CDCETHER \
        -e USB_NET_CDC_NCM -e USB_NET_CDC_SUBSET \
        -e USB_NET_AX8817X -e USB_NET_AX88179_178A -e USB_RTL8152
    # USB-tether ethernet: run a CDC-ECM GADGET on the device-mode DFU port
    # (usb_drd0, apple,force-device-mode) so the M4 appears as a NIC to the host
    # Mac over the same cable — no VBUS/host-mode needed. g_ether (USB_ETH) is
    # the builtin, auto-binding legacy gadget; ConfigFS/ECM kept for flexibility.
    ./scripts/config --file .config \
        -e USB_GADGET -e USB_LIBCOMPOSITE -e USB_U_ETHER \
        -e USB_CONFIGFS -e USB_CONFIGFS_ECM -e USB_CONFIGFS_NCM \
        -e USB_DWC3 -e USB_DWC3_DUAL_ROLE \
        -d USB_ETH -d USB_ETH_RNDIS -d USB_G_NCM
    # No legacy g_ether/RNDIS: macOS does not support RNDIS, so g_ether's
    # RNDIS-first composite enumerated ('RNDIS/Ethernet Gadget') but macOS made
    # no interface. The ECM service builds a PURE CDC-ECM gadget via configfs.
    # It reaches UDC "configured" on T6040, but this macOS host still binds no
    # network interface (ticket 173); retain it for Linux-host diagnostics.
fi
if [ "${HID_RX_REARM:-0}" = "1" ] ||
   [ "${HID_STATE_TRACE:-0}" = "1" ]; then
    # Match the ticket-067 kernel config exactly so the live A/B changes only
    # the DockChannel receive path. UAS remains inert because this variant's
    # DT keeps every USB controller and DART disabled.
    ./scripts/config --file .config -e USB_UAS
fi
if [ "${NVME:-0}" = "1" ]; then
    # Gated ANS/NVMe first-probe image. The standard DT keeps all ANS nodes
    # disabled; these config changes alone probe nothing.
    case "${NVME_MODE:-builtin}" in
        builtin)
            # Original first probe: start ANS during kernel initialization.
            ./scripts/config --file .config \
                -e BLOCK -e BLK_DEV_NVME -e NVME_APPLE -e APPLE_SART
            ;;
        staged)
            # Diagnostic retry: keep SART available, but defer the Apple ANS
            # driver until userspace can stream /dev/kmsg over DockChannel.
            # The generic PCI NVMe host is unrelated to this platform.
            ./scripts/config --file .config \
                -e BLOCK -d BLK_DEV_NVME -e APPLE_SART -m NVME_APPLE
            ;;
        *)
            echo "ERROR: unknown NVME_MODE=${NVME_MODE}; use builtin or staged"
            exit 1
            ;;
    esac
fi
if [ "${GADGET:-0}" = "1" ]; then
    # USB gadget console: plain dwc3 core in peripheral mode (snps,dwc3 DT
    # nodes; the PHY stays as m1n1 configured it) + configfs ACM function.
    # No legacy USB_G_SERIAL: the initramfs builds one gadget per UDC via
    # configfs so whichever port has the tether cable enumerates.
    # NCM/ECM: macOS's ACM driver (AppleUSBCDCComposite) fails to publish
    # interfaces even though the gadget reaches "configured" (verified on HW
    # 2026-07-12); its NCM support is modern and works. Ship both + ACM.
    ./scripts/config --file .config \
        -e USB_SUPPORT -e USB_GADGET -e USB_DWC3 -e USB_DWC3_GADGET \
        -e USB_CONFIGFS -e USB_CONFIGFS_ACM -e U_SERIAL_CONSOLE \
        -e USB_CONFIGFS_NCM -e USB_CONFIGFS_ECM
fi
if [ "${PCIE:-0}" = "1" ]; then
    # Gated T6040 PCIe/WLAN/BT/SD bring-up image.  The separate DT is required
    # because the matching m1n1 PCIe initialization performs invasive clock,
    # PHY, reset, and power-gate writes before handoff.
    ./scripts/config --file .config \
        -e PCI -e PCI_MSI -e PCIE_APPLE \
        -e PINCTRL_APPLE_GPIO -e APPLE_DART \
        -e CFG80211 -e WLAN_VENDOR_BROADCOM \
        -e BRCMUTIL -e BRCMFMAC -e BRCMFMAC_PCIE \
        -e BT -e BT_HCIBCM4377 \
        -e MMC -e MMC_SDHCI -m MMC_SDHCI_PCI
fi
if [ "${USB_HOST:-0}" = "1" ]; then
    # USB2 host image for an external root disk (ticket 009/031/032). Internal
    # NVMe is SPTM-blocked (ticket 008); Linux roots off an external USB2 disk.
    # dwc3-apple glue in host mode over the t8110 DART; usb-storage + uas; ext4
    # and the USB stack are built-in so root is reachable with no modules.
    # No atcphy driver / ATC PHY nodes (USB3/TB deferred): USB2 high-speed only.
    ./scripts/config --file .config \
        -e USB_SUPPORT -e USB -e USB_XHCI_HCD -e USB_XHCI_PLATFORM \
        -e USB_DWC3 -e USB_DWC3_HOST -e USB_DWC3_DUAL_ROLE -e USB_DWC3_APPLE \
        -e APPLE_DART -e IOMMU_SUPPORT \
        -e USB_STORAGE -e USB_UAS \
        -e SCSI -e BLK_DEV_SD \
        -e EXT4_FS
fi
if [ "${DIET:-0}" = "1" ]; then
    echo "== DIET: strip everything the B0 RAM-root does not need =="
    # Why: arm64 defconfig builds a ~50 MiB Image (10.9 MiB XZ). The enrolled
    # boot object must stay under iBoot's (small) limit, so cut the Image, not
    # just the compression. Keep: Apple SoC + dockchannel HID + simpledrm/fbcon
    # + watchdog + initramfs/tmpfs. Drop: every other ARM platform and the big
    # unused subsystems. Asserted below - the build fails if an essential
    # symbol got dropped as a side effect.

    # 1. Every non-Apple ARM64 platform (each pulls its own driver set).
    for sym in $(grep -oE '^CONFIG_ARCH_[A-Z0-9_]+(?==y)' .config 2>/dev/null || \
                 grep -E '^CONFIG_ARCH_[A-Z0-9_]+=y' .config | sed 's/^CONFIG_//;s/=y$//'); do
        case "$sym" in
            ARCH_APPLE) continue ;;                       # ours
            ARCH_MMAP_RND*|ARCH_FORCE*|ARCH_SUSPEND*|ARCH_WANT*|ARCH_HAS*|\
            ARCH_SUPPORTS*|ARCH_USE*|ARCH_KEEP*|ARCH_ENABLE*|ARCH_STACKWALK|\
            ARCH_DMA*|ARCH_INLINE*|ARCH_SPARSEMEM*|ARCH_SELECT*|ARCH_PROC*|\
            ARCH_HIBERNATION*|ARCH_MEMORY*|ARCH_CORRECT*|ARCH_NR_GPIO)
                continue ;;                               # generic capability flags, not platforms
        esac
        ./scripts/config --file .config -d "$sym"
    done

    # 2. Big subsystems with no B0 consumer. Networking: the B0 root has no
    #    network runlevel at all (verified 0 network services), so NET goes.
    ./scripts/config --file .config \
        -d NET -d WIRELESS -d WLAN -d BT -d NFC -d CAN -d RFKILL \
        -d SOUND -d SND -d MEDIA_SUPPORT -d DVB_CORE \
        -d PCI -d PCIEPORTBUS \
        -d SCSI -d BLK_DEV_SD -d BLK_DEV_NVME -d NVME_CORE -d ATA -d MD -d DM_BUILTIN \
        -d USB_SUPPORT -d MMC -d MTD \
        -d EXT4_FS -d BTRFS_FS -d XFS_FS -d F2FS_FS -d JFS_FS -d NTFS3_FS \
        -d FAT_FS -d VFAT_FS -d EXFAT_FS -d NFS_FS -d CIFS -d OVERLAY_FS -d FUSE_FS \
        -d QUOTA -d FSCACHE -d SQUASHFS -d ISO9660_FS -d UDF_FS \
        -d VIRTUALIZATION -d KVM -d XEN -d VFIO \
        -d FTRACE -d KPROBES -d BPF_SYSCALL -d KALLSYMS_ALL \
        -d DEBUG_INFO_BTF -d DEBUG_KERNEL -d DEBUG_MISC \
        -d GCOV_KERNEL -d KUNIT -d STACKPROTECTOR_STRONG \
        -d CRYPTO_USER_API -d CRYPTO_TEST \
        -d INFINIBAND -d STAGING -d COMEDI -d IIO -d W1 \
        -d POWER_RESET -d THERMAL_STATISTICS \
        -d DRM_TTM -d DRM_SCHED -d DRM_PANEL -d DRM_BRIDGE -d DRM_DISPLAY_HELPER \
        -d NLS -d HWMON -d I2C_CHARDEV -d SPI_SPIDEV \
        -d MODULES \
        || true

    # 2b. DIET_CAPABLE: a networking- and block-capable variant of the diet. The
    #     plain diet drops CONFIG_NET (correct for the B0 RAM root, which has zero
    #     network services) and all block/disk support, which blocks WiFi (ticket
    #     139/143) and the root=/dev/ram0 rehearsal (ticket 145). Re-enable just
    #     those stacks; the ~40 non-Apple platforms, sound, media, KVM, ftrace and
    #     the disk filesystems we do not use stay dropped.
    if [ "${DIET_CAPABLE:-0}" = "1" ]; then
        echo "== DIET_CAPABLE: restoring networking + block/ext4 + PCIe =="
        # PCIE_APPLE requires 16 KiB pages (depends on PAGE_SIZE_16KB), which is the
        # native Apple Silicon page size; arm64 defconfig defaults to 4 KiB. Asahi
        # kernels use 16K as standard. NOTE this changes the kernel's page size versus
        # the proven 4K B0 diet kernel, so a DIET_CAPABLE image must be re-smoked
        # before it is trusted for anything but WiFi/PCIe work.
        ./scripts/config --file .config -e ARM64_16K_PAGES -d ARM64_4K_PAGES || true
        ./scripts/config --file .config \
            -e NET -e INET -e PACKET -e UNIX -e SYSVIPC \
            -e WIRELESS -e CFG80211 -e MAC80211 -e WLAN -e WLAN_VENDOR_BROADCOM \
            -e BRCMUTIL -e BRCMFMAC -e BRCMFMAC_PROTO_MSGBUF -e BRCMFMAC_PCIE \
            -e PCI -e PCIEPORTBUS -e PCI_MSI -e PCIE_APPLE \
            -e IOMMU_SUPPORT -e APPLE_DART \
            -e BLK_DEV_RAM -e BLK_DEV_LOOP -e EXT4_FS -e EXT4_USE_FOR_EXT2 \
            -e FW_LOADER -e FW_LOADER_USER_HELPER -e CRC_CCITT \
            -e MTD -e MTD_BLOCK -e MTD_PHRAM \
            || true
        # brd: one 512 MiB ram disk is plenty for the root rehearsal
        ./scripts/config --file .config --set-val BLK_DEV_RAM_COUNT 1 || true
        ./scripts/config --file .config --set-val BLK_DEV_RAM_SIZE 524288 || true
    fi

    # 3. Keep the initramfs/RAM-root essentials explicitly (some may have been
    #    turned off as dependents of the above).
    ./scripts/config --file .config \
        -e BLK_DEV_INITRD -e RD_GZIP -e RD_XZ \
        -e DEVTMPFS -e DEVTMPFS_MOUNT -e TMPFS -e PROC_FS -e SYSFS \
        -e BINFMT_ELF -e BINFMT_SCRIPT -e UNIX98_PTYS \
        -e DRM -e DRM_SIMPLEDRM -e DRM_FBDEV_EMULATION \
        -e FB -e VT -e VT_CONSOLE -e FRAMEBUFFER_CONSOLE -e FONTS \
        -e WATCHDOG -e APPLE_WATCHDOG \
        -e HID -e HID_APPLE -e HID_GENERIC -e INPUT -e INPUT_EVDEV \
        -e APPLE_MAILBOX -e APPLE_RTKIT -e APPLE_DART \
        -e APPLE_DOCKCHANNEL -e APPLE_DOCKCHANNEL_HID -e APPLE_DOCKCHANNEL_TTY \
        -e ARCH_APPLE
    if grep -q "CONFIG_FONT_TER16x32" .config; then
        sed -i 's|# CONFIG_FONT_TER16x32 is not set|CONFIG_FONT_TER16x32=y|' .config
    else
        echo "CONFIG_FONT_TER16x32=y" >> .config
    fi
fi
if [ "${T6040_WIFI_FW_BUILTIN:-0}" = "1" ]; then
    # Ticket 168: keep BCM4388 firmware out of the already size-constrained
    # initramfs.  CONFIG_EXTRA_FIRMWARE paths are relative to this root and do
    # not accept globs, so enumerate the exact apple,mriya WiFi set.  The corpus
    # is pinned to the paired 25F84 restore and lives in persistent /out storage;
    # /private/tmp was purged at midnight on 2026-07-29.
    # The flag must also make the firmware's in-kernel consumer available.
    # This lets it augment either DIET_CAPABLE or the proven MACSMC feature
    # profile; relying on an ambient defconfig module would leave no loader in
    # the bounded RAM image.
    ./scripts/config --file .config \
        -e ARM64_16K_PAGES -d ARM64_4K_PAGES \
        -e NET -e INET -e PACKET -e UNIX \
        -e WIRELESS -e RFKILL -e CFG80211 -e WLAN -e WLAN_VENDOR_BROADCOM \
        -e BRCMUTIL -e BRCMFMAC -e BRCMFMAC_PROTO_MSGBUF -e BRCMFMAC_PCIE \
        -e PCI -e PCIEPORTBUS -e PCI_MSI -e PCIE_APPLE \
        -e IOMMU_SUPPORT -e APPLE_DART \
        -e FW_LOADER \
        || true
    wifi_fw_root="${T6040_WIFI_FW_ROOT:-/out/t6040-paired-fw-25F84/vendorfw}"
    wifi_fw_files=(
        brcmfmac4388c0-pcie.apple,mriya-WLMT-a.txt
        brcmfmac4388c0-pcie.apple,mriya-WLMT-u.txt
        brcmfmac4388c0-pcie.apple,mriya.bin
        brcmfmac4388c0-pcie.apple,mriya.clm_blob
        brcmfmac4388c0-pcie.apple,mriya.sig
        brcmfmac4388c0-pcie.apple,mriya.txcap_blob
        brcmfmac4388c2-pcie.apple,mriya-WLMT-a.txt
        brcmfmac4388c2-pcie.apple,mriya-WLMT-u.txt
        brcmfmac4388c2-pcie.apple,mriya.bin
        brcmfmac4388c2-pcie.apple,mriya.clm_blob
        brcmfmac4388c2-pcie.apple,mriya.sig
        brcmfmac4388c2-pcie.apple,mriya.txcap_blob
    )
    echo "== verify paired 25F84 BCM4388 WiFi firmware =="
    (
        cd "$wifi_fw_root"
        printf '%s\n' \
            "02137cf6fec8e437206f23b6542a9a7cdc8ca39a2ea9b2e07ce2d4bc5409913b  brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-a.txt" \
            "4d0f3187f2e0dd708f5271bffdc43cc63e4d68a3c3449d8c8ff580286eb75bf0  brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.txt" \
            "cd49096c0b0f95caf5e0fd53e1460b8b6ed21f4aba9c314bc0602d6bec77f4bb  brcm/brcmfmac4388c0-pcie.apple,mriya.bin" \
            "822fd43c5502d77d1e7c910e44255bc878b0fa5b046b5133450f6f928098f26b  brcm/brcmfmac4388c0-pcie.apple,mriya.clm_blob" \
            "97ce17756689483a468e52bab27978023727cb7e8b3e372f23a36d410366cae6  brcm/brcmfmac4388c0-pcie.apple,mriya.sig" \
            "7a588168ee5ab1c891e0fadaef56592e84b6c766f91e92b9f08820b822f243fb  brcm/brcmfmac4388c0-pcie.apple,mriya.txcap_blob" \
            "a30428331a385392a04d535d5c106bd2517de0bfb244c58e4e2464c937ff013c  brcm/brcmfmac4388c2-pcie.apple,mriya-WLMT-a.txt" \
            "203251922cfcf95f2233290d75def5ae88e41dfda77af36d8426d9d6db1db3d9  brcm/brcmfmac4388c2-pcie.apple,mriya-WLMT-u.txt" \
            "7cfae8622feeb119c756ae707d26f3a94f1cde44becefacf27ecf1fdc586d93b  brcm/brcmfmac4388c2-pcie.apple,mriya.bin" \
            "af8df65b766a6e2c450892819ecf8422289463e342aa748532c110032140f309  brcm/brcmfmac4388c2-pcie.apple,mriya.clm_blob" \
            "9abb8c1afe0413339f5eca7706150c507a7bca5d244b0a4c6f79e4c28d2ce7cf  brcm/brcmfmac4388c2-pcie.apple,mriya.sig" \
            "2ee489bb7b59b74bad259969344d513b7a6803e83f3563b2ce090df18f53a013  brcm/brcmfmac4388c2-pcie.apple,mriya.txcap_blob" \
            | sha256sum -c -
    )
    wifi_fw_list=""
    for fw in "${wifi_fw_files[@]}"; do
        wifi_fw_list="${wifi_fw_list}${wifi_fw_list:+ }brcm/$fw"
    done
    ./scripts/config --file .config \
        --set-str EXTRA_FIRMWARE "$wifi_fw_list" \
        --set-str EXTRA_FIRMWARE_DIR "$wifi_fw_root"
fi
make ARCH=arm64 olddefconfig >/dev/null
if [ "${MACSMC:-0}" = "1" ]; then
    echo "== assert feature-kernel USB storage path =="
    grep -q '^CONFIG_USB_STORAGE=y$' .config
    grep -q '^CONFIG_USB_UAS=y$' .config
    grep -q '^CONFIG_BLK_DEV_SD=y$' .config
fi
if [ "${T6040_WIFI_FW_BUILTIN:-0}" = "1" ]; then
    echo "== assert built-in BCM4388 WiFi firmware config =="
    grep -q '^CONFIG_FW_LOADER=y$' .config
    grep -q '^CONFIG_BRCMFMAC=y$' .config
    grep -q '^CONFIG_BRCMFMAC_PCIE=y$' .config
    grep -Fq "CONFIG_EXTRA_FIRMWARE=\"$wifi_fw_list\"" .config
    grep -Fq "CONFIG_EXTRA_FIRMWARE_DIR=\"$wifi_fw_root\"" .config
    echo "  12 paired apple,mriya files selected"
fi
if [ "${DIET:-0}" = "1" ]; then
    echo "== DIET: assert every boot-essential symbol survived =="
    diet_fail=0
    if [ "${DIET_CAPABLE:-0}" = "1" ]; then
        echo "== DIET_CAPABLE: assert the networking/block stacks survived =="
        for sym in NET INET PACKET UNIX CFG80211 MAC80211 BRCMFMAC BRCMFMAC_PCIE \
                   PCI PCIE_APPLE APPLE_DART BLK_DEV_RAM EXT4_FS FW_LOADER MTD_PHRAM \
                   ARM64_16K_PAGES PAGE_SIZE_16KB; do
            grep -q "^CONFIG_${sym}=y" .config || { echo "  CAPABLE LOST: CONFIG_${sym}"; diet_fail=1; }
        done
    fi
    for sym in ARCH_APPLE BLK_DEV_INITRD RD_GZIP RD_XZ DEVTMPFS DEVTMPFS_MOUNT \
               TMPFS PROC_FS SYSFS BINFMT_ELF UNIX98_PTYS \
               DRM DRM_SIMPLEDRM DRM_FBDEV_EMULATION FB VT VT_CONSOLE \
               FRAMEBUFFER_CONSOLE FONT_TER16x32 WATCHDOG APPLE_WATCHDOG \
               HID HID_APPLE INPUT INPUT_EVDEV \
               APPLE_MAILBOX APPLE_RTKIT APPLE_DART \
               APPLE_DOCKCHANNEL APPLE_DOCKCHANNEL_HID APPLE_DOCKCHANNEL_TTY; do
        grep -q "^CONFIG_${sym}=y" .config || { echo "  DIET LOST: CONFIG_${sym}"; diet_fail=1; }
    done
    grep -q "^CONFIG_ARM64_SME=y" .config && { echo "  DIET ERROR: ARM64_SME re-enabled"; diet_fail=1; }
    [ "$diet_fail" = "0" ] && echo "  all boot-essential symbols present" || {
        echo "DIET config is missing boot essentials; refusing to build" >&2
        exit 1
    }
fi
if [ "${GADGET:-0}" = "1" ]; then
    echo "-- resulting gadget-relevant config --"
    grep -E "CONFIG_(USB_DWC3|USB_DWC3_GADGET|USB_CONFIGFS|USB_CONFIGFS_ACM)=" .config || true
fi
echo "-- resulting fbcon-relevant config --"
grep -E "CONFIG_(DRM_SIMPLEDRM|DRM_FBDEV_EMULATION|FRAMEBUFFER_CONSOLE|ARM64_SME)=" .config || true
grep -E "CONFIG_(WATCHDOG|APPLE_WATCHDOG)=" .config || true
if [ "${DOCKCHANNEL:-0}" = "1" ]; then
    grep -E "CONFIG_(APPLE_MAILBOX|APPLE_RTKIT|APPLE_DART|HID_APPLE|APPLE_DOCKCHANNEL|APPLE_DOCKCHANNEL_HID)=" .config || true
fi
if [ "${NVME:-0}" = "1" ]; then
    echo "-- resulting ANS/NVMe config --"
    grep -E "CONFIG_(BLK_DEV_NVME|NVME_CORE|NVME_APPLE|APPLE_SART)=" .config || true
fi
if [ "${PCIE:-0}" = "1" ]; then
    echo "-- resulting PCIe/WLAN/BT/SD config --"
    grep -E "CONFIG_(PCIE_APPLE|PINCTRL_APPLE_GPIO|APPLE_DART|BRCMFMAC|BRCMFMAC_PCIE|BT_HCIBCM4377|MMC_SDHCI_PCI)=" .config || true
fi
grep -qE "CONFIG_ARM64_SME=y" .config && echo "WARN: SME still enabled!" || echo "SME disabled OK"

NPROC="${NPROC:-$(nproc)}"
echo "== build parallelism: $NPROC job(s) =="
echo "== build DTB first (validates our DT in the real kbuild) =="
make ARCH=arm64 -j"$NPROC" apple/t6040-j614s.dtb
cp $APPLE/t6040-j614s.dtb /out/ && echo "DTB -> /out/t6040-j614s.dtb"
if [ "${DOCKCHANNEL:-0}" = "1" ]; then
    if [ -f "$APPLE/t6040-j614s-kbd-infra.dts" ]; then
        make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-kbd-infra.dtb
        cp $APPLE/t6040-j614s-kbd-infra.dtb /out/ \
            && echo "DTB -> /out/t6040-j614s-kbd-infra.dtb"
    fi
    make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-kbd.dtb
    cp $APPLE/t6040-j614s-kbd.dtb /out/ \
        && echo "DTB -> /out/t6040-j614s-kbd.dtb"
    make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-dcuart.dtb
    if [ "${TRACKPAD_MOTION:-0}" = "1" ]; then
        cp $APPLE/t6040-j614s-dcuart.dtb \
            /out/t6040-j614s-dcuart-trackpad-motion.dtb \
            && echo "DTB -> /out/t6040-j614s-dcuart-trackpad-motion.dtb"
    elif [ "${HID_STATE_TRACE:-0}" = "1" ]; then
        cp $APPLE/t6040-j614s-dcuart.dtb \
            /out/t6040-j614s-dcuart-hid-state-trace.dtb \
            && echo "DTB -> /out/t6040-j614s-dcuart-hid-state-trace.dtb"
    elif [ "${HID_RX_REARM:-0}" = "1" ]; then
        cp $APPLE/t6040-j614s-dcuart.dtb \
            /out/t6040-j614s-dcuart-hid-rx-rearm.dtb \
            && echo "DTB -> /out/t6040-j614s-dcuart-hid-rx-rearm.dtb"
    else
        cp $APPLE/t6040-j614s-dcuart.dtb /out/ \
            && echo "DTB -> /out/t6040-j614s-dcuart.dtb"
    fi
    if [ "${DOCKCHANNEL_IRQ_TEST:-0}" = "1" ]; then
        make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-dcuart-irq.dtb
        cp $APPLE/t6040-j614s-dcuart-irq.dtb /out/ \
            && echo "DTB -> /out/t6040-j614s-dcuart-irq.dtb"
    fi
    if [ "${DOCKCHANNEL_IRQ_TX_POLL_TEST:-0}" = "1" ]; then
        make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-dcuart-irq-txpoll.dtb
        cp $APPLE/t6040-j614s-dcuart-irq-txpoll.dtb /out/ \
            && echo "DTB -> /out/t6040-j614s-dcuart-irq-txpoll.dtb"
    fi
fi
if [ "${PCIE:-0}" = "1" ]; then
    make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-dcuart-pcie.dtb
    cp $APPLE/t6040-j614s-dcuart-pcie.dtb /out/ \
        && echo "DTB -> /out/t6040-j614s-dcuart-pcie.dtb"
fi
if [ "${MACSMC:-0}" = "1" ]; then
    make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-dcuart-macsmc.dtb
    cp $APPLE/t6040-j614s-dcuart-macsmc.dtb /out/ \
        && echo "DTB -> /out/t6040-j614s-dcuart-macsmc.dtb"
fi
if [ "${USB_HOST:-0}" = "1" ]; then
    USB_HOST_DTB="${USB_HOST_DTS%.dts}.dtb"
    make ARCH=arm64 -j"$NPROC" "apple/$USB_HOST_DTB"
    cp "$APPLE/$USB_HOST_DTB" /out/ \
        && echo "DTB -> /out/$USB_HOST_DTB"
fi

if [ "${1:-}" = "image" ]; then
    echo "== build kernel Image (slow) =="
    make ARCH=arm64 -j"$NPROC" Image
    image_name=Image
    map_name=System.map
    if [ "${MACSMC:-0}" = "1" ]; then
        image_name=Image-macsmc
        map_name=System.map-macsmc
    fi
    if [ "${USB_HOST:-0}" = "1" ]; then
        image_name=Image-usb-host
        map_name=System.map-usb-host
    fi
    if [ "${NVME:-0}" = "1" ]; then
        case "${NVME_MODE:-builtin}" in
            builtin)
                image_name=Image-nvme
                map_name=System.map-nvme
                ;;
            staged)
                image_name=Image-nvme-staged
                map_name=System.map-nvme-staged
                echo "== build staged ANS modules =="
                make ARCH=arm64 -j"$NPROC" \
                    drivers/nvme/host/nvme-core.ko \
                    drivers/nvme/host/nvme-apple.ko
                if [ "${NVME_INIT_TRACE:-0}" = "1" ]; then
                    cp drivers/nvme/host/nvme-core.ko \
                        /out/nvme-core-init-trace.ko
                    cp drivers/nvme/host/nvme-apple.ko \
                        /out/nvme-apple-init-trace.ko
                elif [ "${NVME_FORCE_CONTINUE:-0}" = "1" ]; then
                    cp drivers/nvme/host/nvme-core.ko \
                        /out/nvme-core-force-continue.ko
                    cp drivers/nvme/host/nvme-apple.ko \
                        /out/nvme-apple-force-continue.ko
                elif [ "${NVME_ANS_READ:-0}" = "1" ]; then
                    cp drivers/nvme/host/nvme-core.ko \
                        /out/nvme-core-ans-read.ko
                    cp drivers/nvme/host/nvme-apple.ko \
                        /out/nvme-apple-ans-read.ko
                elif [ "${PMGR_FORCE_ACTIVE:-0}" = "1" ]; then
                    cp drivers/nvme/host/nvme-core.ko \
                        /out/nvme-core-pmgr-force-active.ko
                    cp drivers/nvme/host/nvme-apple.ko \
                        /out/nvme-apple-pmgr-force-active.ko
                elif [ "${NVME_PMGR_SNAPSHOT:-0}" = "1" ]; then
                    cp drivers/nvme/host/nvme-core.ko \
                        /out/nvme-core-pmgr-snapshot.ko
                    cp drivers/nvme/host/nvme-apple.ko \
                        /out/nvme-apple-pmgr-snapshot.ko
                else
                    cp drivers/nvme/host/nvme-core.ko /out/
                    cp drivers/nvme/host/nvme-apple.ko /out/
                fi
                ;;
        esac
    fi
    if [ "${SART_HANDSHAKE_ONLY:-0}" = "1" ]; then
        image_name=Image-sart-handshake
        map_name=System.map-sart-handshake
    fi
    if [ "${SART_DEFERRED_PROBE:-0}" = "1" ]; then
        image_name=Image-sart-deferred
        map_name=System.map-sart-deferred
    fi
    if [ "${SART_TRACE:-0}" = "1" ]; then
        image_name=Image-sart-trace
        map_name=System.map-sart-trace
    fi
    if [ "${NVME_PMGR_SNAPSHOT:-0}" = "1" ]; then
        image_name=Image-nvme-pmgr-snapshot
        map_name=System.map-nvme-pmgr-snapshot
    fi
    if [ "${PMGR_FORCE_ACTIVE:-0}" = "1" ]; then
        image_name=Image-nvme-pmgr-force-active
        map_name=System.map-nvme-pmgr-force-active
    fi
    if [ "${NVME_ANS_READ:-0}" = "1" ]; then
        image_name=Image-nvme-ans-read
        map_name=System.map-nvme-ans-read
    fi
    if [ "${NVME_FORCE_CONTINUE:-0}" = "1" ]; then
        image_name=Image-nvme-force-continue
        map_name=System.map-nvme-force-continue
    fi
    if [ "${NVME_INIT_TRACE:-0}" = "1" ]; then
        image_name=Image-nvme-init-trace
        map_name=System.map-nvme-init-trace
    fi
    if [ "${PCIE:-0}" = "1" ]; then
        image_name=Image-pcie
        map_name=System.map-pcie
    fi
    if [ "${DOCKCHANNEL_IRQ_TEST:-0}" = "1" ]; then
        image_name=Image-dcuart-irq
        map_name=System.map-dcuart-irq
    fi
    if [ "${DOCKCHANNEL_IRQ_TX_POLL_TEST:-0}" = "1" ]; then
        image_name=Image-dcuart-irq-txpoll
        map_name=System.map-dcuart-irq-txpoll
    fi
    if [ "${HID_RX_REARM:-0}" = "1" ]; then
        image_name=Image-hid-rx-rearm
        map_name=System.map-hid-rx-rearm
    fi
    if [ "${HID_STATE_TRACE:-0}" = "1" ]; then
        image_name=Image-hid-state-trace
        map_name=System.map-hid-state-trace
    fi
    if [ "${HID_TYPE_FIX:-0}" = "1" ]; then
        if [ "${MACSMC:-0}" = "1" ]; then
            image_name=Image-macsmc-hid-type-fix
            map_name=System.map-macsmc-hid-type-fix
        else
            image_name=Image-hid-type-fix
            map_name=System.map-hid-type-fix
        fi
    fi
    if [ "${TRACKPAD_MOTION:-0}" = "1" ]; then
        image_name=Image-trackpad-motion
        map_name=System.map-trackpad-motion
    fi
    if [ "${DOCKCHANNEL_EARLYCON:-0}" = "1" ]; then
        image_name=Image-dcuart-earlycon
        map_name=System.map-dcuart-earlycon
    fi
    if [ "${DOCKCHANNEL_NBCON:-0}" = "1" ]; then
        image_name="${image_name}-nbcon"
        map_name="${map_name}-nbcon"
    fi
    # DIET / DIET_CAPABLE are config-only variants that previously had NO name of
    # their own, so they inherited another variant's filename and silently clobbered
    # it — on 2026-07-25 a DIET=1 build overwrote the live-proven 50.8 MiB
    # Image-hid-type-fix (recovered byte-exact from its untouched .gz). Give them a
    # distinct suffix. Ticket 130.
    if [ "${DIET_CAPABLE:-0}" = "1" ]; then
        image_name="${image_name}-dietcap"
        map_name="${map_name}-dietcap"
    elif [ "${DIET:-0}" = "1" ]; then
        image_name="${image_name}-diet"
        map_name="${map_name}-diet"
    fi
    if [ "${T6040_WIFI_FW_BUILTIN:-0}" = "1" ]; then
        image_name="${image_name}-wifi-fw"
        map_name="${map_name}-wifi-fw"
    fi

    # Ticket 154: assert the PAGE SIZE from the built arm64 Image header, before the
    # artifact is published. Ticket 147 existed only because DIET_CAPABLE silently became
    # a 16 KiB-page kernel (PCIE_APPLE depends on PAGE_SIZE_16KB) while every proven boot
    # had used 4 KiB — an ABI-level change the symbol assertions above cannot catch, and
    # which was discoverable afterwards only by decoding the header by hand.
    #
    # Header: magic "ARM\x64" = 0x644d5241 at +56; flags u64 LE at +24, bits 1-2 encode
    # 0=unspecified 1=4K 2=16K 3=64K. NEVER use `strings` for this — Image-b0-dietcap is a
    # 16 KiB kernel yet contains a literal "4K pages" message string, so strings lies.
    image_page_size() {
        local img="$1" magic flags ps
        magic=$(od -An -tx4 -j56 -N4 "$img" 2>/dev/null | tr -d ' \n')
        [ "$magic" = "644d5241" ] || { echo "BADMAGIC:$magic"; return; }
        flags=$(od -An -tu8 -j24 -N8 "$img" 2>/dev/null | tr -d ' \n')
        ps=$(( (flags >> 1) & 3 ))
        case "$ps" in 1) echo 4K ;; 2) echo 16K ;; 3) echo 64K ;; *) echo unspecified ;; esac
    }
    actual_ps=$(image_page_size arch/arm64/boot/Image)
    expect_ps=""
    if [ "${T6040_WIFI_FW_BUILTIN:-0}" = "1" ]; then
        expect_ps=16K   # PCIE_APPLE requires PAGE_SIZE_16KB
    elif [ "${DIET_CAPABLE:-0}" = "1" ]; then
        expect_ps=16K   # PCIE_APPLE requires PAGE_SIZE_16KB
    elif [ "${DIET:-0}" = "1" ]; then
        expect_ps=4K    # the proven B0 page size
    fi
    echo "== Image page size: $actual_ps (header-derived)${expect_ps:+, expected $expect_ps} =="
    if [ -n "$expect_ps" ] && [ "$actual_ps" != "$expect_ps" ]; then
        echo "PAGE SIZE MISMATCH: built $actual_ps but this variant requires $expect_ps" >&2
        echo "  a page-size change is an ABI-level change: it must be re-smoked, not assumed" >&2
        echo "  refusing to publish the artifact" >&2
        exit 1
    fi
    # Cross-check the config agrees with the header, so a stale/edited .config is caught.
    for pair in "4K:ARM64_4K_PAGES" "16K:ARM64_16K_PAGES" "64K:ARM64_64K_PAGES"; do
        want_ps=${pair%%:*}; sym=${pair#*:}
        if [ "$actual_ps" = "$want_ps" ] && ! grep -q "^CONFIG_${sym}=y" .config; then
            echo "PAGE SIZE INCONSISTENT: header says $actual_ps but CONFIG_${sym} is not set" >&2
            exit 1
        fi
    done

    if [ "${T6040_WIFI_FW_BUILTIN:-0}" = "1" ]; then
        for fw in "${wifi_fw_files[@]}"; do
            fw_symbol="_fw_brcm_${fw//[^a-zA-Z0-9_]/_}_bin"
            grep -q " ${fw_symbol}$" System.map || {
                echo "MISSING BUILT-IN FIRMWARE SYMBOL: $fw_symbol" >&2
                exit 1
            }
        done
        echo "  all 12 built-in firmware symbols present in System.map"
    fi
    if [ "${DOCKCHANNEL_NBCON:-0}" = "1" ]; then
        echo "== assert DockChannel nbcon linked =="
        grep -q ' apple_dctty_console_write$' System.map || {
            echo "MISSING NBCON SYMBOL: apple_dctty_console_write" >&2
            exit 1
        }
        grep -q ' apple_dockchannel_send_atomic$' System.map || {
            echo "MISSING NBCON DEPENDENCY: apple_dockchannel_send_atomic" >&2
            exit 1
        }
        grep -q ' CON_PRINTBUFFER | CON_NBCON' \
            drivers/tty/apple_dockchannel_tty.c || {
            echo "MISSING NBCON SOURCE MARKER" >&2
            exit 1
        }
    fi

    # Refuse to silently replace an existing artifact: any Image already in /out may
    # be referenced by a done/ write-up or pinned in a ticket. Set KBUILD_OVERWRITE=1
    # to replace deliberately.
    if [ -e "/out/$image_name" ] && [ "${KBUILD_OVERWRITE:-0}" != "1" ]; then
        echo "REFUSING to overwrite existing /out/$image_name" >&2
        echo "  existing sha256: $(sha256sum "/out/$image_name" 2>/dev/null | cut -d" " -f1)" >&2
        echo "  set KBUILD_OVERWRITE=1 to replace it deliberately, or pick another variant name" >&2
        exit 1
    fi

    cp arch/arm64/boot/Image "/out/$image_name" \
        && echo "Image -> /out/$image_name ($(du -h arch/arm64/boot/Image | cut -f1))"
    # System.map lets t6040-ramdump.py locate __log_buf for a post-mortem console
    # dump when the framebuffer stays blank (hang before simpledrm probes).
    cp System.map "/out/$map_name" && echo "System.map -> /out/$map_name"
    if [ "${T6040_WIFI_FW_BUILTIN:-0}" = "1" ] ||
       [ "${DOCKCHANNEL_NBCON:-0}" = "1" ]; then
        config_name="config-${image_name#Image-}"
        cp .config "/out/$config_name" \
            && echo "config -> /out/$config_name"
    fi
    if [ "${USB_HOST:-0}" = "1" ]; then
        cp .config /out/config-usb-host \
            && echo "config -> /out/config-usb-host"
    fi
    if [ "${HID_RX_REARM:-0}" = "1" ]; then
        cp .config /out/config-hid-rx-rearm \
            && echo "config -> /out/config-hid-rx-rearm"
    fi
    if [ "${HID_STATE_TRACE:-0}" = "1" ]; then
        cp .config /out/config-hid-state-trace \
            && echo "config -> /out/config-hid-state-trace"
    fi
    if [ "${HID_TYPE_FIX:-0}" = "1" ] &&
       [ "${T6040_WIFI_FW_BUILTIN:-0}" = "0" ] &&
       [ "${DOCKCHANNEL_NBCON:-0}" = "0" ]; then
        cp .config /out/config-hid-type-fix \
            && echo "config -> /out/config-hid-type-fix"
    fi
    if [ "${TRACKPAD_MOTION:-0}" = "1" ]; then
        cp .config /out/config-trackpad-motion \
            && echo "config -> /out/config-trackpad-motion"
    fi
    if [ "${DOCKCHANNEL_EARLYCON:-0}" = "1" ]; then
        cp .config /out/config-dcuart-earlycon \
            && echo "config -> /out/config-dcuart-earlycon"
    fi
fi
echo "== done =="
