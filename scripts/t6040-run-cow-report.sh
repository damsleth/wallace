#!/usr/bin/env bash
# Ticket 5011: one fresh boot of the ticket-217 storage-free fault-205
# reproducer (daily301 Image, thin dcuart DTB, initramfs-cow-report) with a
# chosen m1n1 (siq | control) and maxcpus. Waits for T6040_COW_REPORT_END or
# a deadline, then counts kernel faults per reproducer run.
#   usage: t6040-run-cow-report.sh siq|control <maxcpus> <run-dir>
# Requires the rig lease, a running kisd and the M4 at "Running proxy".
set -u
VAR=${1:?siq|control}; N=${2:?maxcpus}; RUN=${3:?run directory}
WALLACE=$(cd "$(dirname "$0")/.." && pwd)
O=/Users/damsleth/Code/linux-build-out
case "$VAR" in
    siq) M1N1=$O/m1n1-siq-20261025/m1n1-siq.bin; H=7cbf67fe88f73647 ;;
    control) M1N1=$O/m1n1-siq-20261025/m1n1-control.bin; H=bf4b24627560759f ;;
    *) echo "variant must be siq or control" >&2; exit 2 ;;
esac
IMAGE=Image-macsmc-hid-type-fix-trackpad-nbcon-ppp-cpufreq-daily301.build1
DTB=t6040-j614s-dcuart.dtb
INITRAMFS=initramfs-cow-report.build1.cpio.gz
DEADLINE=${DEADLINE:-240}
[ ! -e "$RUN" ] || { echo "refusing to reuse $RUN" >&2; exit 2; }
mkdir -p "$RUN"
[ "$(shasum -a 256 "$M1N1" | cut -c1-16)" = "$H" ] || { echo "m1n1 hash mismatch" >&2; exit 1; }
(cd "$O" && printf '%s  %s\n' \
    a9a2096ff47cc8538090ad28cd0bc41b75b09354e90abff8135b3d242d987bc8 "$IMAGE" \
    30b01736b5291aaa864f37f73192ec9877da97ab8ecf5d72c1ca92cf9c8af05d "$DTB" \
    de1a5cd79e030468bff7f7f1fccaf03f2e34d705a4dc77a5aedd927d94fc9b29 "$INITRAMFS" |
    shasum -a 256 -c -) >"$RUN/payload-check.txt" 2>&1 || { echo "payload hash mismatch" >&2; exit 1; }
cd "$WALLACE"
env -u EXTRA_BOOTARGS RIG_AGENT=claude RIG_ENFORCE=1 M1N1DEVICE=/tmp/m1n1 \
    M1N1_BIN="$M1N1" IMAGE=$IMAGE BOOT_MAXCPUS="$N" BOOT_IDLE=nop \
    KERNEL_LOG_ARGS='ignore_loglevel printk.devkmsg=on console=ttydc0 console=tty0' \
    LOG_DIR="$RUN" CHAINLOAD_ATTEMPTS=1 BOOT_WAIT=5 T6040_KEEPALIVE=0 \
    bash scripts/t6040-boot-dcuart.sh $DTB $INITRAMFS >"$RUN/boot-script.out" 2>&1
echo "boot exit=$?" >>"$RUN/boot-script.out"
CON="$RUN/dcuart-console.log"
grep -q 'handoff done' "$RUN/boot-script.out" || { echo "no handoff; see $RUN/boot-script.out"; exit 1; }
grep -q "maxcpus=$N " "$RUN/dcuart-boot.log" || { echo "cmdline lacks maxcpus=$N" >&2; exit 1; }
t=0
while [ "$t" -lt "$DEADLINE" ]; do
    grep -q 'T6040_COW_REPORT_END' "$CON" 2>/dev/null && break
    sleep 5; t=$((t + 5))
done
sleep 5
up=$(tr -d '\r' <"$CON" | grep -aoE 'Brought up [0-9]+ node, [0-9]+ CPUs' | tail -1)
oops=$(tr -d '\r' <"$CON" | grep -acE 'Internal error: Oops|Unable to handle kernel')
end=$(grep -c 'T6040_COW_REPORT_END' "$CON")
runs=$(tr -d '\r' <"$CON" | awk '/T6040_COW_RUN_BEGIN/{r=$NF} /Unable to handle kernel|Internal error: Oops/{c[r]++} END{for (k in c) printf "%s:%d ", k, c[k]}')
echo "RESULT variant=$VAR maxcpus=$N up='$up' report_end=$end faults_total=$oops per_run='${runs:-none}' waited=${t}s"
