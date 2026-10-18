"""stub.sym -> stub.inc (labels the loader patches in) and tests/stub_syms.tcl."""
import re, sys
sym, inc_out, tcl_out = (sys.argv[1:4] + [None]*3)[:3] if len(sys.argv) > 3 else ('stub.sym', 'stub.inc', 'build/stub_syms.tcl')
want = ('pad1t', 'pad1c', 'pad2c', 'rng1', 'rng2', 'ROLE')
inc, tcl = [], []
for l in open(sym):
    m = re.match(r'(\w+):\s*EQU\s*0x([0-9A-Fa-f]+)', l)
    if not m: continue
    if m.group(1) in want: inc.append('%s: EQU 0x%s' % (m.group(1), m.group(2)))
    tcl.append('set ::sym(%s) 0x%s' % (m.group(1), m.group(2)))
open(inc_out, 'w').write('\n'.join(inc) + '\n')
open(tcl_out, 'w').write('\n'.join(tcl) + '\n')
