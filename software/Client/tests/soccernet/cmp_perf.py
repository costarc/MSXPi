"""One table from the $TRACE.perf files of a rig run (perf_node.tcl): python cmp_perf.py H.trace.perf C.trace.perf ...
The traces' .perf siblings are accepted too (a path ending in .trace is read as .trace.perf)."""
import sys


def load(path):
    if path.endswith('.trace'):
        path += '.perf'
    return {k: v for k, v in (line.split(None, 1) for line in open(path).read().splitlines() if line.strip())}


rows = [('node', lambda d: d['role']), ('frames', lambda d: d['frames']), ('fps', None), ('polls/frame', None),
        ('stalled %', None), ('ms XCHG/frame', None), ('timi runs/frame', None), ('link bytes/frame', None)]
print('%-6s %7s %7s %12s %10s %14s %16s %17s' % tuple(r[0] for r in rows))
for path in sys.argv[1:]:
    d = load(path)
    n, s = max(int(d['frames']), 1), max(float(d['seconds']), 1e-9)
    print('%-6s %7d %7.2f %12.2f %10.1f %14.2f %16.2f %17.1f' % (
        d['role'], n, n / s, int(d['xchg_calls']) / n, 100.0 * int(d['stalled_frames']) / n,
        1000.0 * float(d['xchg_seconds']) / n, int(d['timi_runs']) / n, (int(d['link_out']) + int(d['link_in'])) / n))
