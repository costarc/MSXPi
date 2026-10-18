import sys
def load(p):
    d = {}
    tail = ""
    for l in open(p):
        if l.startswith('#'): tail = l.strip(); continue
        k, rest = l.rstrip('\n').split(' ', 1)
        d[int(k)] = rest
    return d, tail
a, ta = load(sys.argv[1]); b, tb = load(sys.argv[2])
common = sorted(set(a) & set(b))
bad = [k for k in common if a[k] != b[k]]
print("H:", len(a), "frames", ta); print("C:", len(b), "frames", tb)
print("compared %d common frames (%s..%s): %s" % (len(common), common[0] if common else '-', common[-1] if common else '-',
      "IDENTICAL" if common and not bad else "%d DIFFER, first at %s" % (len(bad), bad[0] if bad else '-')))
if bad: print(" H:", a[bad[0]]); print(" C:", b[bad[0]])
scenes = sorted(set(v.split()[0] for v in a.values())); print("scenes seen:", scenes)
