"""Python model of the stub's lockstep logic (same arithmetic: 8-bit frames,
16-slot ring, 8-input window, a packet every K frames). Used to find protocol bugs without the emulator."""
import random, sys
class Node:
    def __init__(self, role, delay, k):
        self.role = role
        self.delay = delay
        self.k = k
        self.alt = 0
        self.phase = 0            # frames to wait before the next packet (the stub's kPhase)
        self.nf = 0xFF
        self.own = [0] * 16
        self.rem = [0] * 16
        self.tag = list(range(delay)) + [0xFF] * (16 - delay)
        self.rxSeen = 0
        self.seq = 0
        self.rx = None            # mailbox: (seq, F, [8 vals])
        self.tx = None
        self.sent = None
        self.used = []            # (absolute frame, remote value used)
        self.F = -1               # absolute frame, for checking only
    def local(self, F):           # deterministic "input", changes every 16 frames
        return 0x10 + (((F & 0xFF) >> 4) & 7) * 2 + self.role
    def send(self, back=0):
        base = (self.nf - back + self.delay - 7) & 0xFF
        vals = [self.own[(base + i) & 15] for i in range(8)]
        self.seq = (self.seq + 1) & 0xFF
        self.tx = self.sent = (self.seq, (self.nf - back) & 0xFF, vals)
    def recv(self):
        if self.rx is None or self.rx[0] == self.rxSeen: return
        seq, Fr, vals = self.rx
        self.rxSeen = seq
        g = (Fr + self.delay - 7) & 0xFF
        for v in vals:
            if ((g - self.nf) & 0xFF) < 16:
                self.rem[g & 15] = v
                self.tag[g & 15] = g
            g = (g + 1) & 0xFF
    def have(self):
        return self.tag[self.nf & 15] == self.nf
    def begin_tick(self):
        self.F += 1
        self.nf = (self.nf + 1) & 0xFF
        self.own[(self.nf + self.delay) & 15] = self.local(self.F)
        if self.phase == 0:
            self.phase = self.k - 1
            self.send()
        else:
            self.phase -= 1
    def done_tick(self):
        self.used.append((self.F, self.rem[self.nf & 15], self.own[self.nf & 15]))

def run(frames, lagmax, loss, seed, delay=3, k=1):
    random.seed(seed)
    H, C = Node(0, delay, k), Node(1, delay, k)
    nodes = [H, C]; waiting = [False, False]
    inflight = []                 # (deliver_at, dest, packet)
    t = 0
    for n in nodes: n.begin_tick(); waiting[nodes.index(n)] = True
    while min(len(H.used), len(C.used)) < frames and t < frames * 200:
        t += 1
        for n in nodes:           # transmit what was sent
            if n.tx is not None:
                if random.random() >= loss:
                    inflight.append((t + random.randint(0, lagmax), nodes[1 - nodes.index(n)], n.tx))
                n.tx = None
        # delivery: only the newest due packet per node per step (lossy mailbox)
        due = {}
        for item in list(inflight):
            if item[0] <= t:
                due[id(item[1])] = item; inflight.remove(item)
        for item in due.values(): item[1].rx = item[2]
        for i, n in enumerate(nodes):
            n.recv()
            if n.have():
                n.done_tick(); n.begin_tick()
            elif t % 8 == 0:
                n.alt ^= 1        # stall resend: alternately the usual window and one shifted back by 2D-6 frames
                n.send(max(0, 2 * n.delay - 6) if n.alt else 0)
    # inputs consumed must match: H.rem[F] == C.own[F] and vice versa
    bad = 0
    m = min(len(H.used), len(C.used))
    for F in range(m):
        if H.used[F][1] != C.used[F][2] or C.used[F][1] != H.used[F][2]: bad += 1
    return m, bad, t
bad_runs = 0
for delay, k in ((3, 1), (4, 2), (5, 3), (7, 3)):
    for lagmax, loss in ((0, 0.0), (3, 0.0), (6, 0.1), (12, 0.2)):
        for seed in range(3):
            m, bad, t = run(1200, lagmax, loss, seed, delay, k)
            if m < 1200 or bad: bad_runs += 1
            print("D=%d K=%d lag<=%2d loss=%.1f seed=%d: %4d frames, %3d wrong inputs, %d steps" % (delay, k, lagmax, loss, seed, m, bad, t))
print("%d runs stalled or wrong" % bad_runs)
sys.exit(1 if bad_runs else 0)
