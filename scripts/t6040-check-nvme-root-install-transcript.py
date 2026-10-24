#!/usr/bin/env python3
"""Check a ticket-5005 NVMe root-installer transcript; never operates the rig."""
import argparse
import re
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('transcript', type=Path)
a = p.parse_args()
s = a.transcript.read_text(errors='replace')
errors = []
for pattern in (r'assert', r'I/O error', r'timed out', r'timeout:', r'timeout while',
                r'controller is down', r'crashed', r'translation fault', r'EXFAT-fs.*error',
                r'EXT4-fs error', r'Reset failure', r'ANS did not'):
    if re.search(pattern, s, re.I): errors.append('stop condition: ' + pattern)
# Case-sensitive: re.I would match "debug:" and ANS's benign "PANICLOG".
for pattern in (r'SError', r'panic', r'BUG:', r'Oops:', r'RTKit: Exception', r'NVME-INSTALL STOP'):
    if re.search(pattern, s): errors.append('stop condition: ' + pattern)
need = ['NVME-INSTALL p3 pins OK: start=1586917376 size=356806656 type=EBD0A0A2 guid=EA0DA6DB serial=6add2caf label=linux clean',
        'NVME-INSTALL SD64 source OK: 6442450944 bytes, ext4 4c41b99c-7747-4688-85a5-397bc5d784a2 clean']
for n in need:
    if n not in s: errors.append('missing: ' + n)
src = re.findall(r'copied 6442450944 bytes in .*; source sha256=([0-9a-f]{64})', s)
rr = re.findall(r're-read copy sha256=([0-9a-f]{64})', s)
if len(src) != 1 or rr != src:
    errors.append('copy/re-read hash missing or different')
for step in ('e2fsck -fn', 'e2fsck -fp', 'tune2fs -U 988d97b4-06ba-40d7-8f70-7899bb6fa297', 'resize2fs'):
    if not re.search(re.escape(step) + r' /dev/loop\d+ rc=0', s): errors.append('missing clean ' + step)
if len(re.findall(r'e2fsck -fn /dev/loop\d+ rc=0', s)) != 2:
    errors.append('expected two clean e2fsck -fn checks')
if len(re.findall(r'fsck\.exfat -n \((before|final)\) rc=0', s)) != 2:
    errors.append('expected two clean fsck.exfat -n checks')
dw = re.findall(r'sectors written: disk=(\d+) p3=(\d+)', s)
if len(dw) != 1 or dw[0][0] != dw[0][1]:
    errors.append('whole-disk write sectors missing or differ from p3')
ok = re.findall(r'NVME-INSTALL PASS installed wallace-root.img bytes=17179869184 '
                r'uuid=988d97b4-06ba-40d7-8f70-7899bb6fa297 source_sha256=([0-9a-f]{64}) others_unchanged=yes', s)
if len(ok) != 1 or ok != src:
    errors.append('missing/duplicate PASS line or hash differs')
if errors:
    raise SystemExit('STOP / NOT VALIDATED:\n' + '\n'.join(errors))
print('PASS: SD64 root cloned to p3 wallace-root.img (16 GiB, UUID 988d97b4); hashes match, '
      'ext4 and exFAT clean, writes confined to p3. Preserve and hash the complete transcript.')
