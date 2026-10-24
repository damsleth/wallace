#!/usr/bin/env python3
import sys, re
asm = open('hpm.asm').read().split('\n')
noise = re.compile(r'(autda|xpacd|cmp\tx16, x17|brk\t#0xc472|; loc_|movk\tx17, #0xcda1)')
for i in range(1, len(sys.argv), 2):
    a, b = int(sys.argv[i],16), int(sys.argv[i+1],16)
    print(f'### {sys.argv[i]}..{sys.argv[i+1]}')
    for l in asm:
        m = re.match(r'^(0x[0-9a-f]+):\s+(?:[0-9a-f]{2} ){4}\s*(.*)$', l)
        if not m: continue
        va = int(m.group(1),16)
        if a <= va <= b and not noise.search(l):
            print(f'{m.group(1)}  {m.group(2)}')
