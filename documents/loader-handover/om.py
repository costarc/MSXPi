import os, sys, time
D = os.path.dirname(os.path.abspath(__file__))
res = os.path.join(D, "res.txt")
if os.path.exists(res): os.remove(res)
src = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
src = src.lstrip("﻿")
if src.startswith("@"): src = open(src[1:]).read()
tmp = os.path.join(D, "cmd.tmp")
open(tmp, "w").write(src)
os.replace(tmp, os.path.join(D, "cmd.tcl"))
t = time.time() + float(os.environ.get("OM_TIMEOUT", "30"))
while time.time() < t:
    if os.path.exists(res):
        time.sleep(0.05); print(open(res, errors="replace").read()); sys.exit(0)
    time.sleep(0.1)
print("TIMEOUT"); sys.exit(1)
