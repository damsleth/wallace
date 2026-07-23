#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPORT="$ROOT/scripts/t6040-hid-trace-auto-report"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/t6040-hid-trace-auto.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

mkdir -p \
    "$TMP/sys/devices/dockchannel" \
    "$TMP/sys/devices/dchid" \
    "$TMP/proc/bus/input" \
    "$TMP/dev/input" \
    "$TMP/etc"

printf '%s\n' 'console=ttydc0' >"$TMP/cmdline"
printf '%s\n' '3.24.0' >"$TMP/etc/alpine-release"
printf '%s\n' \
    'ordinary kernel line' \
    'HIDTRACE irq status=0x1' \
    'HIDTRACE event type=keyboard' >"$TMP/dmesg"
printf '%s\n' 'irq_count: 4' >"$TMP/sys/devices/dockchannel/dc_trace"
printf '%s\n' 'events: 2' >"$TMP/sys/devices/dchid/hid_trace"
printf '%s\n' 'N: Name="Apple Internal Keyboard"' \
    >"$TMP/proc/bus/input/devices"
printf '%s\n' 'major minor  #blocks  name' >"$TMP/proc/partitions"
touch "$TMP/dev/input/event0"

common_env=(
    CMDLINE_FILE="$TMP/cmdline"
    SYS_ROOT="$TMP/sys"
    PROC_ROOT="$TMP/proc"
    DEV_ROOT="$TMP/dev"
    RELEASE_FILE="$TMP/etc/alpine-release"
    DMESG_FILE="$TMP/dmesg"
    TRACE_AUTO_DELAY_SECONDS=0
)

env "${common_env[@]}" "$REPORT" >"$TMP/disabled.out"
test ! -s "$TMP/disabled.out"

printf '%s\n' 'console=ttydc0 t6040.hid_trace_auto=10' >"$TMP/cmdline"
env "${common_env[@]}" "$REPORT" >"$TMP/near-value.out"
test ! -s "$TMP/near-value.out"

printf '%s\n' 'console=ttydc0 xt6040.hid_trace_auto=1' >"$TMP/cmdline"
env "${common_env[@]}" "$REPORT" >"$TMP/near-name.out"
test ! -s "$TMP/near-name.out"

printf '%s\n' 'console=ttydc0 t6040.hid_trace_auto=1' >"$TMP/cmdline"
env "${common_env[@]}" "$REPORT" >"$TMP/enabled.out"

grep -qF '===== T6040 HID TRACE AUTO REPORT BEGIN =====' "$TMP/enabled.out"
grep -qF 'HIDTRACE irq status=0x1' "$TMP/enabled.out"
grep -qF 'HIDTRACE event type=keyboard' "$TMP/enabled.out"
grep -qF 'irq_count: 4' "$TMP/enabled.out"
grep -qF 'events: 2' "$TMP/enabled.out"
grep -qF 'Apple Internal Keyboard' "$TMP/enabled.out"
grep -qF 'event0' "$TMP/enabled.out"
grep -qF 'major minor  #blocks  name' "$TMP/enabled.out"
grep -qF '===== T6040 HID TRACE AUTO REPORT END =====' "$TMP/enabled.out"

test "$(grep -c '^--- .*_trace$' "$TMP/enabled.out")" -eq 2

: >"$TMP/dmesg"
for line_number in $(seq 1 205); do
    printf 'HIDTRACE capped line %s\n' "$line_number" >>"$TMP/dmesg"
done
env "${common_env[@]}" "$REPORT" >"$TMP/capped.out"
test "$(grep -c '^HIDTRACE capped line ' "$TMP/capped.out")" -eq 200
! grep -qxF 'HIDTRACE capped line 5' "$TMP/capped.out"
grep -qxF 'HIDTRACE capped line 6' "$TMP/capped.out"
grep -qxF 'HIDTRACE capped line 205' "$TMP/capped.out"

echo "t6040 HID trace auto-reporter host test: PASS"
