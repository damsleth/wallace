#!/usr/bin/env bash
# t6040-enroll-guard.sh — fail-closed guard for enrolling a B0 raw m1n1 object
# onto the DEDICATED m1n1 macOS System volume (tickets 082/101).
#
# RUN THIS ON THE M4, from the MAIN macOS (Full Security) — NOT from the
# m1n1-enrolled boot. It validates (1) the object is an approved B0 object by
# SHA-256, and (2) the target is EXACTLY the dedicated m1n1 System volume by its
# pinned APFS Volume UUID (not by name alone). Only then does it print — or, with
# --confirm-enroll, run — the exact `kmutil configure-boot` command. It can never
# target any other volume (e.g. Macintosh HD), and refuses any unlisted object.
#
# This guard performs no security-policy (bputil) change and no cold boot; those
# stay separate, maintainer-driven steps.
set -euo pipefail

# --- pinned identity of the dedicated m1n1 System volume (maintainer-confirmed) ---
EXPECT_UUID="B7FB1EC3-1BA0-4DCB-B57D-C8E9A0AE1E63"
EXPECT_NAME="m1n1"
TARGET="${TARGET:-/Volumes/m1n1}"

# --- approved objects (SHA-256 -> label). Anything else is refused. ---
#  3aabde2d… dual-mode GRAPHICAL (dwm, 10 s window) — ticket 163, the intended daily driver
#  59622e78… graphical, window-free               — ticket 161 fallback if the window misbehaves
#  f290833c… B0 milestone (Alpine, untethered)    — ticket 101 live-proven
#  46237ade… dual-mode (EARLY_PROXY_TIMEOUT=5) — conditionally reviewed preferred object
#  2371ee5d… pure auto-boot                    — ticket-100 live-proven fallback
#  1394c345… bare proxy-m1n1                    — ROLLBACK object (restores dev loop)
#
# 3aabde2d added 2026-07-26. It was NOT tethered-smoke-tested, because a window-carrying
# object's own 10 s window catches chainload.py's handshake. It is approved on different
# evidence: its payload region [0x10c000,end) is BYTE-IDENTICAL to 59622e78, which WAS
# live-proven as dwm with a working keyboard (both sha256
# 3b1ac51f69d1b5d9a102fe71b3bf953c3c3d9433dfe193e723ec679641e1a6c7), and the only differing
# bytes lie inside the m1n1 loader, which was itself live-proven both ways in ticket 140.
#  3cfdaf24… macsmc dual-mode (dwm + battery/thermals + USB-tether ECM) — ticket 165/167/173
APPROVED_HASHES="\
3cfdaf247827ca765026ab2a8419e43d43af19c1f22f34b1b2eeb30e6e07ef62 macsmc-dualmode-dwm-ecm
3aabde2d4639639f5f0603d9eac9e3c05ee1f8b3c27c2aa53901e9a471b2efa8 dualmode-graphical-dwm
59622e78685961a322308643b03eae6db0dd3ee985b5674e0b3e6831d605a270 graphical-dwm-window-free
f290833c8a9dd7ea4086571b925e6b775c113dd3b4626a7ef2644ebc76fd03fd b0-milestone-alpine
46237ade7e314cd752e1482930e21b62319e1b0b707a0f23e86392701555f0c9 dual-mode-EARLY_PROXY_TIMEOUT
2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b pure-autoboot-fallback
1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b rollback-bare-proxy-m1n1"

OBJ="${1:-}"
CONFIRM="${2:-}"
if [ -z "$OBJ" ]; then
    echo "usage: TARGET=/Volumes/m1n1 $0 <object.bin> [--confirm-enroll]" >&2
    echo "  validates identity + object hash, prints the exact kmutil command;" >&2
    echo "  add --confirm-enroll to actually run it." >&2
    exit 2
fi
[ -f "$OBJ" ] || { echo "GUARD FAIL: object not found: $OBJ" >&2; exit 1; }

# 1) object SHA-256 must be an approved object
sha=$(shasum -a 256 "$OBJ" | awk '{print $1}')
label=$(awk -v s="$sha" '$1==s{print $2}' <<<"$APPROVED_HASHES")
[ -n "$label" ] || {
    echo "GUARD FAIL: object SHA-256 not approved:" >&2
    echo "  $sha" >&2
    echo "  ($OBJ) — refusing to enroll an unlisted object." >&2
    exit 1
}

# 2) target must be the exact m1n1 System volume, keyed on its APFS Volume UUID
[ "$TARGET" = "/Volumes/m1n1" ] || {
    echo "GUARD FAIL: target must be /Volumes/m1n1 (got: $TARGET)" >&2; exit 1; }
info=$(diskutil info "$TARGET") || {
    echo "GUARD FAIL: 'diskutil info $TARGET' failed (is it mounted?)" >&2; exit 1; }
uuid=$(awk -F': *' '/Volume UUID/{print $2; exit}' <<<"$info" | tr -d '[:space:]')
name=$(awk -F': *' '/Volume Name/{print $2; exit}' <<<"$info" | sed 's/[[:space:]]*$//')
role=$(grep -iE 'Volume Role|APFS Role|Designated Role' <<<"$info" || true)
[ "$uuid" = "$EXPECT_UUID" ] || {
    echo "GUARD FAIL: Volume UUID mismatch — WRONG VOLUME." >&2
    echo "  got      $uuid" >&2
    echo "  expected $EXPECT_UUID" >&2
    exit 1; }
[ "$name" = "$EXPECT_NAME" ] || {
    echo "GUARD FAIL: Volume Name '$name' != '$EXPECT_NAME'" >&2; exit 1; }
grep -qi 'System' <<<"$role" || {
    echo "GUARD FAIL: target does not report an APFS System role: ${role:-<none>}" >&2; exit 1; }

echo "GUARD PASS"
echo "  object : $OBJ"
echo "  sha256 : $sha"
echo "  kind   : $label"
echo "  target : $TARGET  (UUID $uuid, name '$name', System)"
echo

# The exact enrollment command (raw m1n1 contract from ticket 080).
set -- kmutil configure-boot -c "$OBJ" --raw --entry-point 2048 --lowest-virtual-address 0 -v "$TARGET"
echo "Exact enroll command:"
# No sudo: enrollment happens in 1TR, where the shell is already root and sudo is not
# available at all (maintainer, 2026-07-26). Printing `sudo kmutil ...` sent someone to 1TR
# with a command that cannot run as written.
printf ' '; printf ' %q' "$@"; echo; echo

if [ "$CONFIRM" = "--confirm-enroll" ]; then
    echo ">>> --confirm-enroll set — running now <<<"
    exec "$@"
fi
echo "(validation only. Re-run with --confirm-enroll to execute, or run the command above.)"
