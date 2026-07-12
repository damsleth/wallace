#!/usr/bin/env bash
# T6040 kernel build harness (runs INSIDE the arm64 Linux build container).
#
# Invocation from the host (script + patches must be visible in /out):
#   cp ~/Code/wallace/scripts/t6040-kbuild.sh ~/Code/wallace/patches/*.patch ~/Code/linux-build-out/
#   podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard kbuild \
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

BRANCH=feature/m4-m5-minimal-device-trees
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
cp /src/$APPLE/t6040-pmgr.dtsi   $APPLE/
cp /src/$APPLE/Makefile          $APPLE/

echo "== apply flokli's t6040 CODE patches (aic locked-sysreg skip + idle=nop) =="
# CRITICAL: the build checks out COMMITTED code and only copies in DT files, so any
# uncommitted code edits on the host (e.g. the irq-apple-aic.c hyp-mode sysreg
# comment-out) are NOT in the build. Apply flokli's proven t6040 bring-up code
# patches here so they actually land. Patch disables BOTH the
# SYS_IMP_APL_VM_TMR_FIQ_ENA_EL2 and SYS_ICH_HCR_EL2 writes in aic_init_cpu (they
# trap on M4 raw-boot) and adds a working arm64 idle=[wfi|nop] param.
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
echo "-- verify the two traps are gone from aic_init_cpu --"
if sed -n '/static int aic_init_cpu/,/PMC FIQ/p' drivers/irqchip/irq-apple-aic.c | grep -qE "^\s*sysreg_clear_set_s\(SYS_(IMP_APL_VM_TMR_FIQ_ENA|ICH_HCR)_EL2"; then
    echo "WARN: a locked-sysreg write is still active in aic_init_cpu!"
else
    echo "aic_init_cpu locked-sysreg writes disabled OK"
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
    # Local fix: apple,poll-mode for the dockchannel mailbox — on t6040 the
    # dockchannel-uart AIC line (ADT irq 360) never asserts (verified by
    # scanning all 4096 AIC inputs with FIFO flags latched+unmasked), so the
    # driver polls the FIFO like m1n1 and the KIS agent do.
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
if [ "${NVME:-0}" = "1" ]; then
    # Gated ANS/NVMe first-probe image. These default to modules, but the
    # minimal initramfs ships no modules, so make the storage stack built-in.
    # The standard DT keeps all ANS nodes disabled; this alone probes nothing.
    ./scripts/config --file .config \
        -e BLOCK -e BLK_DEV_NVME -e NVME_APPLE -e APPLE_SART
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
make ARCH=arm64 olddefconfig >/dev/null
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
    grep -E "CONFIG_(BLK_DEV_NVME|NVME_APPLE|APPLE_SART)=" .config || true
fi
grep -qE "CONFIG_ARM64_SME=y" .config && echo "WARN: SME still enabled!" || echo "SME disabled OK"

NPROC=$(nproc)
echo "== build DTB first (validates our DT in the real kbuild) =="
make ARCH=arm64 -j"$NPROC" apple/t6040-j614s.dtb
cp $APPLE/t6040-j614s.dtb /out/ && echo "DTB -> /out/t6040-j614s.dtb"
if [ "${DOCKCHANNEL:-0}" = "1" ]; then
    make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-kbd-infra.dtb
    cp $APPLE/t6040-j614s-kbd-infra.dtb /out/ \
        && echo "DTB -> /out/t6040-j614s-kbd-infra.dtb"
    make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-kbd.dtb
    cp $APPLE/t6040-j614s-kbd.dtb /out/ \
        && echo "DTB -> /out/t6040-j614s-kbd.dtb"
    make ARCH=arm64 -j"$NPROC" apple/t6040-j614s-dcuart.dtb
    cp $APPLE/t6040-j614s-dcuart.dtb /out/ \
        && echo "DTB -> /out/t6040-j614s-dcuart.dtb"
fi

if [ "${1:-}" = "image" ]; then
    echo "== build kernel Image (slow) =="
    make ARCH=arm64 -j"$NPROC" Image
    image_name=Image
    map_name=System.map
    if [ "${NVME:-0}" = "1" ]; then
        image_name=Image-nvme
        map_name=System.map-nvme
    fi
    cp arch/arm64/boot/Image "/out/$image_name" \
        && echo "Image -> /out/$image_name ($(du -h arch/arm64/boot/Image | cut -f1))"
    # System.map lets t6040-ramdump.py locate __log_buf for a post-mortem console
    # dump when the framebuffer stays blank (hang before simpledrm probes).
    cp System.map "/out/$map_name" && echo "System.map -> /out/$map_name"
fi
echo "== done =="
