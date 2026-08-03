# T6040 USB physical-port ADT capture preflight (2026-07-21)

The USB-host smoke packet is otherwise ready, but forcing all three DWC3
controllers would also force the unknown physical port carrying DebugUSB. This
preflight resolves that blocker with one ADT-only capture before building a
single-port host DTB.

## Reviewed helper

`scripts/t6040-dump-usb-adt.py`, SHA-256
`b6e7423626eb141b6631a4c126259d7cb50a2907954c575c1622d7bdc016e4f6`.

Independent review verified that the helper:

- refuses any transport except `M1N1DEVICE=/tmp/m1n1` (KIS);
- does not import `m1n1.setup`, touch the PMU panic counter, use `ProxyUtils`,
  allocate target RAM, change baud, or call any MMIO accessor;
- performs only a proxy NOP, boot-args pointer query, and bulk reads of the
  trusted boot-args/ADT RAM ranges;
- atomically refuses an existing output path and writes the full authoritative
  ADT only to a host-side file with mode 0600;
- prints the raw ADT SHA-256 and a supplemental USB/ATC/Type-C filtered view.

No new m1n1 or Linux image is involved in this experiment.

## Exact proposed run

After CJ approves the ADT-capture rig ticket:

```sh
scripts/rig-lease.sh acquire codex "ADT-only USB physical-port map" b6e74236
RIG_AGENT=codex bash scripts/t6040-debugusb-console.sh reboot

RAW=/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt
LOG=/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.log
test ! -e "$RAW" && test ! -e "$LOG"
pkill -f '^cat /tmp/m1n1$' 2>/dev/null || true
set -o pipefail
M1N1DEVICE=/tmp/m1n1 \
PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH=/Users/damsleth/Code/m1n1/proxyclient \
/Users/damsleth/Code/m1n1/venv/bin/python \
    scripts/t6040-dump-usb-adt.py --raw-output "$RAW" | tee "$LOG"
rc=$?
RIG_AGENT=codex bash scripts/t6040-debugusb-console.sh
scripts/rig-lease.sh release codex --state healthy
exit "$rc"
```

If capture or console recovery fails, release the lease `--state wedged`
instead. Do not read MMIO, initialize USB, or boot Linux under this ticket.

## Offline continuation

Hash and inspect the captured ADT for DWC3/ATC/connector/port phandles. If it
identifies the physical mapping, build a DTB enabling only the controller for
the attached drive and leaving the DebugUSB port disabled, then repeat the
artifact and cross-review checks. If the ADT has no mapping, return to CJ with
the evidence and request an explicit decision on the disclosed three-port role
risk; do not silently fall back to the current all-port image.
