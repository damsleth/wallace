#!/usr/bin/env bash
# Mechanical preflight for every T6040 image or boot object.
#
# WHY THIS EXISTS: the Norwegian keyboard layout has been forgotten three times,
# and a ten-day-stale $OUT/Image once produced an entire evening of false
# hardware diagnoses. A checklist someone has to remember to read fails the same
# way the memory it replaces fails. This runs the checks instead.
#
# Usage:
#   scripts/t6040-image-preflight.sh --kernel <Image> [--initramfs <cpio.gz>] \
#       [--object <raw-object.bin>] [--bootargs '<args>'] [--m1n1 <m1n1.bin>]
#
# Exit 0 only if every applicable invariant holds. See docs/BUILD_RECIPE.md.
set -uo pipefail

KERNEL="" INITRAMFS="" OBJECT="" BOOTARGS="" M1N1=""
while [ $# -gt 0 ]; do
    case "$1" in
        --kernel) KERNEL=$2; shift 2 ;;
        --initramfs) INITRAMFS=$2; shift 2 ;;
        --object) OBJECT=$2; shift 2 ;;
        --bootargs) BOOTARGS=$2; shift 2 ;;
        --m1n1) M1N1=$2; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

FAIL=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }

# --- kernel -----------------------------------------------------------------
if [ -n "$KERNEL" ]; then
    echo "kernel: $KERNEL"
    if [ ! -f "$KERNEL" ]; then
        fail "kernel file does not exist"
    else
        # A whole missing subsystem means the wrong kernel, not broken hardware.
        for sym in pcie-apple macsmc dockchannel-hid; do
            if [ "$(strings -a "$KERNEL" | grep -ci "$sym")" -gt 0 ]; then
                pass "kernel contains $sym"
            else
                fail "kernel contains NO '$sym' -- wrong or stale kernel"
            fi
        done
        # Control string: proves the grep pipeline works, so a 0 above is real.
        if [ "$(strings -a "$KERNEL" | grep -c 'Linux version')" -gt 0 ]; then
            pass "kernel version string readable: $(strings -a "$KERNEL" |
                grep -m1 'Linux version' | cut -c1-58)"
        else
            fail "cannot read a version string -- strings/grep unreliable here"
        fi
    fi
fi

# --- initramfs --------------------------------------------------------------
if [ -n "$INITRAMFS" ]; then
    echo "initramfs: $INITRAMFS"
    if [ ! -f "$INITRAMFS" ]; then
        fail "initramfs file does not exist"
    else
        LIST=$(gzip -dc "$INITRAMFS" 2>/dev/null | cpio -it 2>/dev/null)
        member() { printf '%s\n' "$LIST" | grep -qx "./$1"; }

        # MANDATORY: Norwegian console keymap (AGENTS.md non-negotiable).
        if member etc/wallace-no.bmap; then
            pass "Norwegian keymap present (etc/wallace-no.bmap)"
        else
            fail "NO Norwegian keymap -- every image must ship one"
        fi
        # And init must actually load it; shipping it unused is the same bug.
        # Extract ./init and grep THAT, not the whole archive: a whole-archive
        # match is a false positive on Alpine's stock /etc/conf.d/loadkmap and
        # on the busybox binary's own applet-name table, so an image whose init
        # never loads the keymap still passed (found 2026-08-04 reviewing the
        # OBEX image, which shipped no keymap at all yet "passed" this line).
        # bsdtar, not `cpio --to-stdout`: macOS ships bsdcpio, whose
        # --to-stdout silently yields nothing here. bsdtar -xOf - is the
        # extraction pattern already proven elsewhere in this repo.
        INIT_TXT=$(gzip -dc "$INITRAMFS" 2>/dev/null | \
            bsdtar -xOf - ./init 2>/dev/null || true)
        if [ "$(printf '%s' "$INIT_TXT" | grep -ac 'loadkmap')" -gt 0 ]; then
            pass "init loads the keymap (loadkmap call in ./init)"
        else
            fail "keymap is never loaded -- no loadkmap call in ./init"
        fi

        for m in init bin/busybox; do
            if member "$m"; then pass "member $m"; else fail "missing member $m"; fi
        done
        # exfatprogs installs to /usr/sbin; the sdroot-fsck image has it there,
        # so checking only ./sbin/fsck.exfat warned on an image that does ship
        # the tool (observed 2026-08-04 on the ticket-215 repair image).
        if member sbin/fsck.exfat || member usr/sbin/fsck.exfat; then
            pass "member fsck.exfat (SD repair available)"
        else
            warn "no fsck.exfat -- a dirty SD64 cannot be repaired in place"
        fi
        for m in lib/firmware/brcm/brcmfmac4388c0-pcie.apple,mriya-WLMT-u.bin \
                 lib/firmware/brcm/brcmbt4388c2-apple,mriya-u.bin; do
            if member "$m"; then
                pass "firmware $(basename "$m")"
            else
                warn "missing $(basename "$m") -- WiFi/BT probe before switch_root"
            fi
        done
    fi
fi

# --- bootargs ---------------------------------------------------------------
if [ -n "$BOOTARGS" ]; then
    echo "bootargs: $BOOTARGS"
    # Every console= receives printk, but the LAST becomes /dev/console, which is
    # what init's shell reads. With ttydc0 last the panel shows a shell that
    # ignores the keyboard.
    LASTCON=$(printf '%s\n' "$BOOTARGS" | tr ' ' '\n' | grep '^console=' | tail -1)
    case "$LASTCON" in
        console=tty0) pass "last console is tty0 (panel keeps /dev/console)" ;;
        "") fail "no console= at all" ;;
        *) fail "last console is '$LASTCON'; put console=tty0 last or the keyboard is dead" ;;
    esac
    case "$BOOTARGS" in
        *console=ttydc0*) pass "ttydc0 present (serial logging works)" ;;
        *) warn "no console=ttydc0 -- no serial log for this boot" ;;
    esac
    case "$BOOTARGS" in
        *maxcpus=1*) pass "maxcpus=1 (ticket 205 fail-stop limit respected)" ;;
        *maxcpus=*) warn "maxcpus>1: ticket 205 kills processes above one core" ;;
        *) fail "no maxcpus= -- ticket 205 makes an unbounded core count unsafe" ;;
    esac
fi

# --- m1n1 -------------------------------------------------------------------
if [ -n "$M1N1" ]; then
    echo "m1n1: $M1N1"
    if [ "$(strings -a "$M1N1" | grep -cE 'Vectoring to next stage|Boot policy: sip0|m1n1')" -eq 0 ]; then
        warn "control string absent; window check below may be meaningless"
    fi
    if [ "$(strings -a "$M1N1" | grep -c 'Waiting for proxy connection')" -eq 0 ]; then
        pass "window-free m1n1 (boots straight through)"
    else
        warn "this m1n1 waits for a proxy -- correct for a rollback object only"
    fi
fi

# --- object -----------------------------------------------------------------
if [ -n "$OBJECT" ]; then
    echo "object: $OBJECT"
    if [ ! -f "$OBJECT" ]; then
        fail "object file does not exist"
    else
        SZ=$(command ls -l "$OBJECT" | awk '{print $5}')
        if [ $((SZ % 16384)) -eq 0 ]; then
            pass "16 KiB aligned ($((SZ / 16384)) pages, $SZ bytes)"
        else
            fail "NOT 16 KiB aligned ($SZ bytes) -- iBoot will never run it"
        fi

        # Check what the object ACTUALLY CONTAINS, not a file sitting next to it.
        # Checking a standalone initramfs proves nothing about the object: the two
        # can diverge, and member offsets/sizes shift whenever a member changes
        # size, so cached offsets from a previous build are wrong.
        EMBEDDED=$(python3 - "$OBJECT" <<'PY'
import gzip, subprocess, sys
blob = open(sys.argv[1], 'rb').read()
pos, found = 0, False
while True:
    pos = blob.find(b'\x1f\x8b\x08', pos)
    if pos < 0:
        break
    try:
        raw = gzip.decompress(blob[pos:])          # trailing garbage is tolerated
    except Exception:
        try:
            d = gzip.zlib.decompressobj(gzip.zlib.MAX_WBITS | 16)
            raw = d.decompress(blob[pos:])
        except Exception:
            pos += 1
            continue
    # Require the newc magic at offset 0. A false gzip magic inside another
    # member can decompress to something that merely CONTAINS "TRAILER!!!",
    # which cpio then cannot parse -- that produced an empty listing and a
    # confident set of false failures.
    if not raw.startswith(b'070701'):
        pos += 1
        continue
    names = set(subprocess.run(['cpio', '-t'], input=raw,
                               capture_output=True).stdout.decode(errors='replace').split())
    for want in ('./init', './bin/busybox', './etc/wallace-no.bmap', './sbin/fsck.exfat'):
        print(f'{"OK" if want in names else "NO"} {want}')
    print(f'{"OK" if b"loadkmap" in raw else "NO"} loadkmap-call-in-init')
    found = True
    break
if not found:
    print('NOFIND embedded-initramfs')
PY
)
        while read -r verdict what; do
            case "$verdict" in
                OK) pass "object embeds $what" ;;
                NO) if [ "$what" = "./sbin/fsck.exfat" ]; then
                        warn "object does NOT embed $what (no in-place SD repair)"
                    else
                        fail "object does NOT embed $what"
                    fi ;;
                NOFIND) warn "could not locate an embedded initramfs to inspect" ;;
            esac
        done <<EOF
$EMBEDDED
EOF
    fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "preflight: OK"
    exit 0
fi
echo "preflight: $FAIL FAILURE(S) -- do not enroll or boot this"
exit 1
