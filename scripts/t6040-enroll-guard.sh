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
#  74e78ad8… same as 679fe133 but maxcpus=5 and a ttydc0 getty — 5 cores instead of 1.
#  Proven on the window-free twin c48080b9: shell reached, nproc 5, and all five CPUs
#  accumulating user AND system time in /proc/stat (so the scheduler really uses them),
#  with wlan0 + hci0 up and zero oops. maxcpus>=6 is blocked by a kernel fault in
#  unpack_to_rootfs, bisected 2026-07-29 — do not raise it past 5 yet. The getty means
#  this payload can finally be driven from the host over KIS instead of read at the panel.
#  679fe133… dual-mode WiFi/BT/PPP, no HIDF, v116 scan fix — ticket 187 (reviewed 2026-07-29).
#  Sol's 969ba852 with one member replaced: the kernel is rebuilt with
#  patches/t6040-brcmfmac-bss-info-v116.patch, without which brcmfmac discards every scan
#  result ("BSS info version 116 unsupported") and WiFi can associate with nothing. m1n1
#  prefix ee58fa40 (from PCIe source 04e8829c, BIT(4) reset fix + 10 s DTR window), DTB
#  0afb98ae (pwren-gpios + antenna-sku), initramfs 0ff9415f — the last two byte-identical to
#  sol's reviewed object. Contains NO apple/tpmtfw-j614s.bin, so it needs no ticket-126
#  firmware-upload exception. Strict verify PASS, 2158×16 KiB, both xz members PASS the
#  minilzlib harness.
#  16a4c594… daily driver v5 (2026-07-30): the ANS-crash fix + Oslo time + battery bar. v4's
#  first boot proved the driver+DT correct THROUGH identify/namespace-enumeration, then the ANS
#  FIRMWARE crashed: our loader never touches NVMe, so Linux inherited iBoot's LIVE ANS and the
#  driver's apple_rtkit_wake path adopted foreign RTKit state (every Asahi machine gets a
#  quiesced ANS from m1n1's nvme_shutdown; ours early-returns on !nvme_initialized). Kernel
#  patch t6040-nvme-apple-force-clean-ans-boot forces the stop + clean assert/reinit/boot path.
#  Both fixes binary-asserted in the packed kernel member. Image: Europe/Oslo localtime,
#  battery bar via macsmc-battery capacity/status read_file (charge_now absent), same
#  everything otherwise. Expect on boot: "ANS left running by boot stage; forcing clean reset"
#  then a clean rtkit boot, /dev/nvme0n1 + friends, and CJ's 128 GiB exFAT at /mnt/nvme.
#  53264755… daily driver v4 (2026-07-30): v3 done RIGHT + kbd backlight + L2C SError decode.
#  v3's kernel silently LACKED the nvme cherry-picks (stale container clone — kbuild now
#  fetch+reset+cleans, and packing verifies drivers by string-grep of the packed member:
#  't8132-nvme-ans2' asserted in THIS object's kernel gzip). Adds /sys/class/leds/kbd_backlight
#  (fpwm0 + pwm-leds, ADT-measured) and yuka's L2C_ERR fault-address print on SError (needed by
#  the 126 HIDF live capture). Same image as v3 (099e1c72). First live nvme-apple probe on
#  T6040 happens on THIS object's first boot; dual-mode window + rollback is the net.
#  65f6fbe3… daily driver v3 (2026-07-30) — SUPERSEDED by 53264755: its kernel is missing the
#  nvme-apple t8132 driver entirely (build staleness); everything else works. Do not re-enroll.
#  layout (yuka ad890806 + the two 26.x gates: no LINEAR_SQ/UNKNOWN_CTRL, no Set Features/NoQ
#  which crashes ANS), t6040 node re-verified against OUR ADT (irqs 1530-33+2583 = t6041's,
#  sart 0xc000). Every boot cycles CC.EN on the controller holding macOS — CJ requested this as
#  the daily storage path 2026-07-30. /mnt/nvme automounts only a CJ-created exFAT/FAT32
#  partition (Linux cannot mount APFS, so macOS volumes are untouchable by construction);
#  t6040-data-sync prefers it. ⚠ NOT chainload-verified (CJ on the machine): the nvme-apple
#  probe on T6040 is first-run — dual-mode window + rollback is the net. If it wedges at boot,
#  the window still opens BEFORE the kernel runs.
#  beb29334… daily driver v2 (2026-07-30): v1 + wall-clock RTC (SPMI abbey PMU rtc_offset@0x2100
#  + smc-rtc + HCTOSYS), i3status config (battery all / macsmc-ac / wlan0 / /data / local time),
#  PATH fix (t6040-* helpers visible in st + dmenu), WiFi auto-associate from CJ's wpa.conf
#  (derived hex PSK baked, ::once: so it cannot stall boot) + one-shot ntpd. ⚠ NOT yet
#  chainload-verified (CJ was using the machine): the SPMI controller at 0x509014000 is a new
#  Linux probe surface — verify one tethered boot before or accept the dual-mode/rollback net.
#  c1529d4c… THE DAILY DRIVER (2026-07-30): i3 + dwm fallback, cpufreq (P cores to 4.512 GHz
#  via the freq-mult-overflow patch), WiFi (19-BSS scan verified), BT, 7 GiB /data +
#  SD/USB automount, ttydc0 getty, maxcpus=5. NO HIDF (the live tpmtfw upload kills the
#  machine — A/B/A-bisected 2026-07-30, needs an attended panel-watch to diagnose; magicmouse
#  binds and fails -ENOENT harmlessly). Boot hang fixed: acm-console UDC bind moved out of
#  sequential sysinit. Exact payload combo live-verified by chainload same night: both
#  cpufreq policies + verified 4512000 transition, wlan0 scan 19 BSS, hci0, /data mounted,
#  Xorg+i3+i3bar running. Strict verify PASS, 2609×16 KiB, initramfs decodes to 99.5 MiB
#  in the minilzlib harness (kernel member is gzip — m1n1 payload.c native).
#  5931f9c3… macsmc dual-mode v3 (dwm + keyboard + battery/thermals SRAM-fixed) — 165
APPROVED_HASHES="\
5931f9c3d1f785f2a25cd40754fec1f38078efbc3ceaa952288c529bbc7527f8 macsmc-dualmode-dwm-v3-sramfix
3aabde2d4639639f5f0603d9eac9e3c05ee1f8b3c27c2aa53901e9a471b2efa8 dualmode-graphical-dwm
59622e78685961a322308643b03eae6db0dd3ee985b5674e0b3e6831d605a270 graphical-dwm-window-free
f290833c8a9dd7ea4086571b925e6b775c113dd3b4626a7ef2644ebc76fd03fd b0-milestone-alpine
46237ade7e314cd752e1482930e21b62319e1b0b707a0f23e86392701555f0c9 dual-mode-EARLY_PROXY_TIMEOUT
2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b pure-autoboot-fallback
1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b rollback-bare-proxy-m1n1
679fe1335876c14b51e30de8c615addf5e171b7f53f92eec8e489173a79f5d76 dualmode-wifi-bt-ppp-no-hidf-v116
74e78ad848af95c1fa26e8cf610ceedc801176adbc43413e674cb0075ecbb9e0 dualmode-everything-5core
c1529d4c8007e251606f14a86e6d307aad04b3472f2527c41f01b85c58072773 dwm-i3-everything-cpufreq-5core
beb293340965d53f1ed3a1f14cde748bd1326d8fa6f1f6f158dc3e39bd2cb6cc dwm-i3-v2-rtc-wifi-5core
65f6fbe339d6749f724fc763adafaefd0951374b7decbe755640b84c42d6bc1e dwm-i3-v3-nvme-rtc-5core
53264755c8b086292815a28143c801edc7e38e74dde9552fa88cdab4634ca930 dwm-i3-v4-nvme-kbl-5core
16a4c5946fa1e0ed9a3810ed6bc4aab5cc19a2daf21006523271f9290360fa83 dwm-i3-v5-ansfix-tz-5core"

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
