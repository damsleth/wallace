#!/usr/bin/env python3
"""Extract function bodies from hpm.asm by (demangled substring) name. usage: fn.py NAME [NAME...]"""
import sys, re, subprocess
asm = open('hpm.asm').read().split('\n')
# index functions: lines ending with ':' and not starting with 0x
funcs = []  # (name, start_line)
for i,l in enumerate(asm):
    if l and not l.startswith('0x') and l.endswith(':') and not l.startswith(' '):
        funcs.append((l[:-1], i))
def demangle(n):
    try:
        return subprocess.run(['c++filt', n], capture_output=True, text=True).stdout.strip()
    except Exception:
        return n
names = {}
for n,i in funcs:
    names[n] = i
dem = {n: demangle(n) for n,_ in funcs}
if len(sys.argv) > 1 and sys.argv[1] == '--list':
    for n,i in funcs:
        print(f"{i}\t{dem[n]}")
    sys.exit(0)
for want in sys.argv[1:]:
    for idx,(n,i) in enumerate(funcs):
        if want in dem[n] or want in n:
            end = funcs[idx+1][1] if idx+1 < len(funcs) else len(asm)
            print(f"=== {dem[n]}  [{n}] lines {i}-{end}")
            print('\n'.join(asm[i:end]))
            print()
