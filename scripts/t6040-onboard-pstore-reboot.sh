#!/bin/sh
# Ticket 5020: warm-reboot pstore check on the standalone M4.
#   t6040-onboard-pstore-reboot.sh          write a marker to the kernel log, then reboot cleanly
#   t6040-onboard-pstore-reboot.sh check    after the reboot: is the marker in console-ramoops-0?
# The 5019 ramoops has pmsg_size=0 (no /dev/pmsg0), so the marker goes through
# /dev/kmsg and the ramoops console region.
set -eu
STATE=/root/.wallace-5020-marker
if [ "${1:-}" = check ]; then
  [ -s "$STATE" ] || { echo "no marker recorded in $STATE"; exit 2; }
  M=$(cat "$STATE")
  mountpoint -q /sys/fs/pstore || mount -t pstore pstore /sys/fs/pstore
  ls -l /sys/fs/pstore
  if grep -qF "$M" /sys/fs/pstore/console-ramoops-0 2>/dev/null; then
    echo "PASS: $M survived the warm reboot"
  else
    echo "FAIL: $M not in /sys/fs/pstore/console-ramoops-0"; exit 1
  fi
  exit 0
fi
[ "$(cat /sys/block/nvme0n1/queue/write_cache)" = "write through" ] || { echo "write_cache is not write through, aborting"; exit 1; }
M="wallace-5020-marker-$(date +%s)"
echo "$M" > "$STATE"
echo "<4>$M" > /dev/kmsg
sync
echo "marker $M written; rebooting cleanly"
exec reboot
