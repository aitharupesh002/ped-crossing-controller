#!/usr/bin/env python3
"""Remove cells that OpenLane/ORFS mark 'dont_use' (lpflow_*, probe*) from a liberty file,
so Yosys/ABC does not map to them. Usage: filter_lib.py in.lib out.lib"""
import re, sys
src = open(sys.argv[1]).read()
out, i, removed = [], 0, 0
pat = re.compile(r'\n\s*cell\s*\(\s*"?(sky130_fd_sc_hd__(?:lpflow_\w+|probe\w*|probec\w*))"?\s*\)\s*\{')
while True:
    m = pat.search(src, i)
    if not m:
        out.append(src[i:]); break
    out.append(src[i:m.start()])
    depth, j = 1, m.end()
    while depth:
        c = src[j]
        depth += (c == '{') - (c == '}')
        j += 1
    i = j; removed += 1
open(sys.argv[2], 'w').write(''.join(out))
print(f"removed {removed} dont_use cells")
