"""Generates stub.asm (the script tables are random but fixed by the seed)."""
import random
random.seed(1985)
def script(n, fire):
    out = []
    for i in range(n):
        r = random.random()
        if r < 0.35: v = 0
        elif r < 0.35 + fire: v = 0x10
        else: v = random.choice([1, 2, 4, 8, 1 | 4, 2 | 8])
        out.append(v)
    return out
SCRIPT = [0x10, 0, 0x10, 0x02, 0x10, 0, 0x10, 0x08]   # fire pulses walk the menus
def db(l): return "        defb    " + ",".join("$%02X" % x for x in l)
tmpl = open(__file__.replace('gen_stub.py', 'stub.tmpl.asm')).read()
open(__file__.replace('gen_stub.py', 'stub.asm'), 'w').write(
    tmpl.replace('@SCR0@', db(script(8, 0.3))).replace('@SCR1@', db(script(8, 0.25))))
