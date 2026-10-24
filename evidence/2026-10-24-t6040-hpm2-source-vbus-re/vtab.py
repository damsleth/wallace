#!/usr/bin/env python3
"""Decode arm64e kext vtables. usage: vtab.py KEXT CLASS [slot ...]
Entries: target = 0xfffffe0007004000 + (raw & 0xffffffff); diversifier = (raw>>32)&0xffff."""
import sys, struct, subprocess, re, bisect
kext, cls = sys.argv[1], sys.argv[2]
want = [int(s,16) for s in sys.argv[3:]]
info = subprocess.run(['ipsw','macho','info',kext], capture_output=True, text=True).stdout
segs = []
for m in re.finditer(r'LC_SEGMENT_64 sz=0x[0-9a-f]+ off=(0x[0-9a-f]+)-0x[0-9a-f]+ addr=(0x[0-9a-f]+)-(0x[0-9a-f]+)', info):
    segs.append((int(m.group(2),16), int(m.group(3),16), int(m.group(1),16)))
def va2off(va):
    for lo,hi,off in segs:
        if lo <= va < hi: return va - lo + off
    raise ValueError(hex(va))
data = open(kext,'rb').read()
nm = subprocess.run(['nm', kext], capture_output=True, text=True).stdout.split('\n')
syms = {}
funcs = []
for l in nm:
    p = l.split()
    if len(p) != 3: continue
    a = int(p[0],16); syms.setdefault(p[2], a)
    if p[1] in 'tT': funcs.append((a, p[2]))
funcs.sort()
faddrs = [a for a,_ in funcs]
def fname(va):
    i = bisect.bisect_right(faddrs, va) - 1
    if i < 0: return '?'
    a, n = funcs[i]
    d = subprocess.run(['c++filt', n], capture_output=True, text=True).stdout.strip()
    return d if a == va else f'{d}+0x{va-a:x}'
ztv = syms.get('__ZTV' + str(len(cls)) + cls)
if ztv is None:
    sys.exit('no vtable for ' + cls)
base = va2off(ztv) + 0x10
n = 0
out = []
while True:
    raw = struct.unpack_from('<Q', data, base + n*8)[0]
    if raw == 0: break
    tgt = 0xfffffe0007004000 + (raw & 0xffffffff)
    div = (raw >> 32) & 0xffff
    slot = n*8
    if not want or slot in want:
        out.append(f'+0x{slot:x}\tdiv={div:04x}\t{tgt:#x}\t{fname(tgt)}')
    n += 1
    if n > 600: break
print('\n'.join(out))
