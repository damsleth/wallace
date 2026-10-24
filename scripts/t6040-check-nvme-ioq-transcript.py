#!/usr/bin/env python3
"""Check the read-only IOQ test transcript; never operate the rig."""
import argparse
import re
from pathlib import Path
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('transcript', type=Path)
a = p.parse_args()
s = a.transcript.read_text(errors='replace')
errors = []
for pattern in (r'assert', r'I/O error', r'timed out', r'timeout:', r'timeout while',
                r'controller is down', r'crashed', r'translation fault'):
    if re.search(pattern, s, re.I): errors.append('stop condition: ' + pattern)
# Case-sensitive: re.I made BUG: match "debug:" and panic match "PANICLOG".
for pattern in (r'SError', r'panic', r'BUG:', r'Oops:', r'RTKit: Exception',
                r'NVME-READONLY STOP', r'NVME-READONLY kernel stop'):
    if re.search(pattern, s): errors.append('stop condition: ' + pattern)
if len(re.findall(r'NVME-READONLY START bytes=67108864 chunk=16384 passes=4 ', s)) != 1:
    errors.append('expected exactly one test start')
if len(re.findall(r'NVME-READONLY PASS direct_reads=16384 bytes=268435456 repeated_bytes_match=yes', s)) != 1:
    errors.append('missing/duplicate complete test PASS')
if 'NVME-READONLY test exit=0 ' not in s:
    errors.append('missing successful test exit')
before = re.findall(r'block stats before: ([0-9 ]+)', s)
after = re.findall(r'block stats after: ([0-9 ]+)', s)
if len(before) != 1 or len(after) != 1:
    errors.append('missing/duplicate block statistics')
else:
    b, e = ([int(x) for x in v[0].split()] for v in (before, after))
    if len(b) != 17 or len(e) != 17:
        errors.append('unexpected block-stat layout; inspect manually')
    else:
        if e[0] - b[0] < 16384 or e[2] - b[2] < 524288:
            errors.append('insufficient completed device reads/sectors')
        if any(e[i] != b[i] for i in (*range(4, 8), *range(11, 17))):
            errors.append('write/discard/flush statistics changed')
        if e[8] != 0: errors.append('I/O remains in flight')
if 'NVME-READONLY namespaces n1=1954210120 n2=6144 n3=262144 sectors' not in s:
    errors.append('missing pinned namespace topology')
aux_before = re.findall(r'aux stats before: ([0-9 ]+)\| ([0-9 ]+)', s)
aux_after = re.findall(r'aux stats after: ([0-9 ]+)\| ([0-9 ]+)', s)
if len(aux_before) != 1 or len(aux_after) != 1:
    errors.append('missing/duplicate auxiliary-namespace statistics')
elif aux_before != aux_after:
    errors.append('auxiliary namespace statistics changed (n2/n3 must see no I/O)')
if errors:
    raise SystemExit('STOP / NOT VALIDATED:\n' + '\n'.join(errors))
print('PASS: 16,384 direct reads, repeated data match, device counters verified, no writes/discards/flushes or recognized faults.')
print('Preserve and hash the complete transcript. This does not validate NVMe writes or daily-driver readiness.')
