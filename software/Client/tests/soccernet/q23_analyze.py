"""Q2 and Q3 from a $TRACE.q23 log (q23_node.tcl): python q23_analyze.py H.trace.q23

Q2: does INL send a datagram inside UDP_SEND (nc_send), or when its timer runs?  For every S (ETH_SEND_FRAME) it says
what came just before: N (inside nc_send) or T (the timer) or something else.
Q3: frames taken from the driver (G) per run of the timer (T), and G outside any timer run.
"""
import collections
import sys

events = []
for line in open(sys.argv[1]):
    code, ms = line.split()
    events.append((code, float(ms)))

xchg = sum(1 for c, _ in events if c == 'X')
print('XCHG calls', xchg, ' events', len(events))
count = collections.Counter(c for c, _ in events)
print('totals', dict(count))

# Q2: the last N / T / R before each S
before = collections.Counter()
last = None
for code, _ in events:
    if code in 'NRTX':
        last = code
    elif code == 'S':
        before[last] += 1
print('Q2: ETH_SEND_FRAME preceded (last of N=nc_send, R=nc_recv, T=timer, X=call entry) by', dict(before))

# Q3: G per timer run
per_run = []
current = None
loose = 0
for code, _ in events:
    if code == 'T':
        if current is not None:
            per_run.append(current)
        current = 0
    elif code == 'G':
        if current is None:
            loose += 1
        else:
            current += 1
    elif code == 'Y' and current is not None:
        per_run.append(current)
        current = None
if current is not None:
    per_run.append(current)
hist = collections.Counter(per_run)
print('Q3: timer runs', len(per_run), ' frames taken (G) per run:', dict(sorted(hist.items())), ' G outside a run:', loose)

# how often the timer runs, and how many of those had a frame waiting (I with a frame is not visible: count I per T)
print('timer runs per XCHG call %.2f, G per XCHG call %.2f, S per XCHG call %.2f' % (
    count['T'] / max(xchg, 1), count['G'] / max(xchg, 1), count['S'] / max(xchg, 1)))
