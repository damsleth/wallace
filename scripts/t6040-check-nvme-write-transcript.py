#!/usr/bin/env python3
"""Check an exFAT NVMe write-test transcript (ticket 211/5003); never operates the rig."""
import argparse
import re
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('transcript', type=Path)
p.add_argument('--mode', choices=('write', 'verify'), required=True)
p.add_argument('--expect-sha256', help='verify mode: the hash recorded by the write run')
a = p.parse_args()
s = a.transcript.read_text(errors='replace')
errors = []
for pattern in (r'assert', r'I/O error', r'timed out', r'timeout:', r'timeout while',
                r'controller is down', r'crashed', r'translation fault', r'EXFAT-fs.*error',
                r'Reset failure', r'ANS did not'):
    if re.search(pattern, s, re.I): errors.append('stop condition: ' + pattern)
# Case-sensitive: re.I would match "debug:" and ANS's benign "PANICLOG".
for pattern in (r'SError', r'panic', r'BUG:', r'Oops:', r'RTKit: Exception', r'NVME-WRITE STOP'):
    if re.search(pattern, s): errors.append('stop condition: ' + pattern)
dw = re.findall(r'sectors written: disk=(\d+) p3=(\d+)', s)
if len(dw) != 1 or dw[0][0] != dw[0][1]:
    errors.append('whole-disk write sectors missing or differ from p3')
if f'NVME-WRITE mode={a.mode};' not in s:
    errors.append(f'missing mode={a.mode} start line')
if 'NVME-WRITE pins OK: p3 start=1586917376 size=356806656 type=EBD0A0A2 guid=EA0DA6DB serial=6add2caf label=linux' not in s:
    errors.append('missing pinned-partition confirmation')
passes = re.findall(rf'NVME-WRITE PASS mode={a.mode} bytes=1073741824 sha256=([0-9a-f]{{64}}) others_unchanged=yes', s)
if len(passes) != 1:
    errors.append('missing/duplicate PASS line')
reads = re.findall(r'read back 1073741824 bytes .*; sha256=([0-9a-f]{64}) expected=([0-9a-f]{64})', s)
if len(reads) != 1 or reads[0][0] != reads[0][1]:
    errors.append('read-back hash missing or mismatched')
if a.mode == 'write':
    w = re.findall(r'NVME-WRITE write sha256=([0-9a-f]{64})', s)
    if len(w) != 1 or not reads or w[0] != reads[0][0]:
        errors.append('write hash missing or differs from read-back')
    if len(re.findall(r'fsck\.exfat -n \((before|after-write|final)\) rc=0', s)) != 3:
        errors.append('expected three clean fsck.exfat -n checks')
else:
    if not a.expect_sha256 or not reads or reads[0][0] != a.expect_sha256:
        errors.append('verify: read-back hash does not equal the write run hash')
    if len(re.findall(r'fsck\.exfat -n \((before|final)\) rc=0', s)) != 2:
        errors.append('expected two clean fsck.exfat -n checks')
wc = re.findall(r'NVME-WRITE dir=(\S+) write_cache=(write back|write through) fua=(\d)', s)
if len(wc) != 1:
    errors.append('missing dir/write_cache line')
if errors:
    raise SystemExit('STOP / NOT VALIDATED:\n' + '\n'.join(errors))
print(f'PASS: {a.mode} of 1 GiB on the pinned exFAT linux partition ({wc[0][0]}, '
      f'write_cache={wc[0][1]}, fua={wc[0][2]}); hashes match, exFAT clean, other partitions untouched.')
print('Preserve and hash the complete transcript.')
