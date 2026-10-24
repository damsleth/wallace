#!/usr/bin/env python3
"""Generate scripts/t6040-nvmeroot-init from scripts/t6040-sdroot-init.

The NVMe daily root (ticket 5005) is the proven SD root with one change: the
SD/GL9755 identity gates are replaced by the internal-SSD pins of probe 5001
(evidence/2026-10-25-t6040-5001-exfat-linux-identity.md). Generating it keeps
the shutdown tmpfs, dirty-flag repair, keymap and helper logic identical, and
makes the delta reviewable as exactly this script.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ROOT_UUID = '988d97b4-06ba-40d7-8f70-7899bb6fa297'
ROOT_BYTES = 17179869184   # 16 GiB ext4 wallace-root.img

GATE = r'''# Internal SSD: wait for the namespace, then apply the probe-5001 pins
# (evidence/2026-10-25-t6040-5001-exfat-linux-identity.md) before any write.
n=0
while [ ! -b "$PART" ] && [ "$n" -lt 30 ]; do
    "$BB" sleep 1
    n=$((n + 1))
done
[ -b "$PART" ] || stop "$PART did not appear after ${n}s"
n=0
while { [ ! -b /dev/nvme0n2 ] || [ ! -b /dev/nvme0n3 ]; } && [ "$n" -lt 10 ]; do
    "$BB" sleep 1
    n=$((n + 1))
done
ns_size() { "$BB" cat "/sys/block/$1/size" 2>/dev/null; }
[ ! -e /dev/nvme1 ] || stop "unexpected second NVMe controller"
[ "$(ns_size nvme0n1)" = 1954210120 ] && [ "$(ns_size nvme0n2)" = 6144 ] &&
    [ "$(ns_size nvme0n3)" = 262144 ] && [ ! -e /dev/nvme0n4 ] ||
    stop "unexpected NVMe namespace topology"
case "$("$BB" cat /sys/class/nvme/nvme0/transport):$("$BB" cat /sys/class/nvme/nvme0/model)" in
    apple-nvme:APPLE\ SSD\ AP1024Z*) ;;
    *) stop "unexpected NVMe controller identity" ;;
esac
# Every partition and namespace except the root container is read-only.
for d in /dev/nvme0n1p1 /dev/nvme0n1p2 /dev/nvme0n1p4 /dev/nvme0n2 /dev/nvme0n3; do
    [ -b "$d" ] || stop "missing $d"
    "$BB" blockdev --setro "$d" || stop "cannot set $d read-only"
done
[ ! -e /dev/nvme0n1p5 ] || stop "unexpected fifth partition"
nhex() { "$BB" dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | "$BB" hexdump -v -e '1/1 "%02x"'; }
[ "$("$BB" cat /sys/block/nvme0n1/nvme0n1p3/start)" = 1586917376 ] || stop "p3 start mismatch"
[ "$("$BB" cat /sys/block/nvme0n1/nvme0n1p3/size)" = 356806656 ] || stop "p3 size mismatch"
[ "$("$BB" cat /sys/block/nvme0n1/queue/logical_block_size)" = 4096 ] || stop "unexpected logical block size"
# GPT entry array at LBA 2 (byte 8192); p3 is slot 2 (+256).
[ "$(nhex /dev/nvme0n1 8448 16)" = a2a0d0ebe5b9334487c068b6b72699c7 ] || stop "p3 GPT type is not Microsoft Basic Data"
[ "$(nhex /dev/nvme0n1 8464 16)" = dba60dea3529cb49a996b982dd646f24 ] || stop "p3 GPT unique GUID mismatch"
[ "$(nhex /dev/nvme0n1 8480 16)" = 00ced20b00000000ff5b7b0e00000000 ] || stop "p3 GPT LBA range mismatch"
[ "$("$BB" dd if="$PART" bs=1 skip=3 count=8 2>/dev/null)" = "EXFAT   " ] || stop "p3 is not exFAT"
[ "$(nhex "$PART" 100 4)" = af2cdd6a ] || stop "exFAT serial is not 0x6add2caf"
[ "$(nhex "$PART" 7733248 12)" = 83056c0069006e0075007800 ] || stop 'exFAT label is not "linux"'
say "NVMe exFAT linux partition pinned (p3, serial 6add2caf)"

'''


def main():
    s = (ROOT / 't6040-sdroot-init').read_text()

    def sub(old, new):
        nonlocal s
        if s.count(old) != 1:
            raise SystemExit(f'expected exactly one occurrence of: {old[:60]!r}')
        s = s.replace(old, new)

    sub('# Fail-closed /init for the ticket-204 SD root.\n#\n'
        '# SD64 remains one exFAT partition. wallace-root.img is a 6 GiB ext4 image\n'
        '# used as /.',
        '# Fail-closed /init for the NVMe daily root (ticket 5005), generated from\n'
        '# t6040-sdroot-init by t6040-gen-nvmeroot-init.py; only the storage gates\n'
        '# differ. The exFAT "linux" partition (nvme0n1p3) holds wallace-root.img,\n'
        '# a 16 GiB ext4 image used as /.')
    sub('PART=/dev/mmcblk0p1\nPCI_DEV=/sys/bus/pci/devices/0000:02:00.0\n'
        'ROOT_UUID=4c41b99c-7747-4688-85a5-397bc5d784a2\nROOT_BYTES=6442450944\n',
        f'PART=/dev/nvme0n1p3\nROOT_UUID={ROOT_UUID}\nROOT_BYTES={ROOT_BYTES}\n')
    start = s.index('# PCIe is enumerated asynchronously')
    end = s.index('# exFAT VolumeFlags is the little-endian word at byte 106')
    s = s[:start] + GATE + s[end:]
    for old, new in (('SD64 exFAT is dirty', 'linux exFAT is dirty'),
                     ('SD64 exFAT still dirty', 'linux exFAT still dirty'),
                     ('"SD64 did not mount as exFAT read-only"', '"linux exFAT did not mount read-only"'),
                     ('"SD64 read-only identity mount would not unmount"',
                      '"linux exFAT read-only identity mount would not unmount"'),
                     ('"SD64 did not mount as exFAT read-write"', '"linux exFAT did not mount read-write"'),
                     ('"cannot move SD64 under the shutdown tmpfs"', '"cannot move the linux exFAT under the shutdown tmpfs"'),
                     ('"cannot expose SD64 at /mnt/sd"', '"cannot expose the linux exFAT at /mnt/sd"')):
        sub(old, new)
    leftovers = [l for l in s.splitlines() if any(k in l for k in ('GL9755', 'mmcblk', 'PCI_DEV', 'SD64'))]
    if leftovers:
        raise SystemExit('SD-specific lines remain:\n' + '\n'.join(leftovers))
    out = ROOT / 't6040-nvmeroot-init'
    out.write_text(s)
    out.chmod(0o755)
    print(f'{out} written')


if __name__ == '__main__':
    main()
