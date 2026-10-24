#!/usr/bin/env python3
"""Summarise functions: keep calls (with vtable slot), strings, immediates into w1/w2/w3/w8/w9, cmp, branches-with-targets flagged. usage: sum.py NAME..."""
import sys, re, subprocess
asm = open('hpm.asm').read().split('\n')
funcs = []
for i,l in enumerate(asm):
    if l and not l.startswith('0x') and l.endswith(':') and not l.startswith(' '):
        funcs.append((l[:-1], i))
cache={}
def dem(n):
    if n not in cache:
        cache[n]=subprocess.run(['c++filt', n], capture_output=True, text=True).stdout.strip()
    return cache[n]
keep = re.compile(r'(\bbl\b|\bblraa\b|\bblr\b|\bbraa\b|; "|mov\tw[0-9]+, #|movk\tw[0-9]+, #|mov\tx[0-9]+, #|movk\tx[0-9]+, #|cmp\tw[0-9]+, #|cmn\t|tbz|tbnz|cbz|cbnz|b\.|ldr\tx[0-9]+, \[x[0-9]+, #0x[0-9a-f]+\]|ldrb\tw[0-9]+, \[x19, #|strb\tw[0-9]+, \[x19, #|ldr\tw[0-9]+, \[x19, #|str\tw[0-9]+, \[x19, #|\bret\b|retab|IOSleep|IODelay)')
for want in sys.argv[1:]:
    for idx,(n,i) in enumerate(funcs):
        d = dem(n)
        if want in d or want in n:
            end = funcs[idx+1][1] if idx+1 < len(funcs) else len(asm)
            print(f"=== {d}  @{asm[i+1].split(':')[0]}  ({end-i} lines)")
            for l in asm[i+1:end]:
                if keep.search(l):
                    # compact: strip bytes
                    l2 = re.sub(r'^(0x[0-9a-f]+):\s+(?:[0-9a-f]{2} ){4}\s*', r'\1  ', l)
                    print(l2)
            print()
