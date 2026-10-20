"""Python model of the stub's lockstep logic (same arithmetic: 8-bit frames,
16-slot ring, 8-input window). Used to find protocol bugs without the emulator."""
import random, sys
DELAY = 3
class Node:
    def __init__(self, role):
        self.role = role
        self.nf = 0xFF
        self.own = [0] * 16
        self.rem = [0] * 16
        self.tag = [0, 1, 2] + [0xFF] * 13
        self.rxSeen = 0
        self.seq = 0
        self.rx = None            # mailbox: (seq, F, [8 vals])
        self.tx = None
        self.used = []            # (absolute frame, remote value used)
        self.F = -1               # absolute frame, for checking only
    def local(self, F):           # deterministic "input", changes every 16 frames
        return 0x10 + (((F & 0xFF) >> 4) & 7) * 2 + self.role
    def send(self):
        base = (self.nf + DELAY - 7) & 0xFF
        vals = [self.own[(base + i) & 15] for i in range(8)]
        self.seq = (self.seq + 1) & 0xFF
        self.tx = (self.seq, self.nf, vals)
    def recv(self):
        if self.rx is None or self.rx[0] == self.rxSeen: return
        seq, Fr, vals = self.rx
        self.rxSeen = seq
        g = (Fr + DELAY - 7) & 0xFF
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
        self.own[(self.nf + DELAY) & 15] = self.local(self.F)
        self.send()
    def done_tick(self):
        self.used.append((self.F, self.rem[self.nf & 15], self.own[self.nf & 15]))

def run(frames, lagmax, loss, seed):
    random.seed(seed)
    H, C = Node(0), Node(1)
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
                n.send()          # stall resend
    # inputs consumed must match: H.rem[F] == C.own[F] and vice versa
    bad = 0
    m = min(len(H.used), len(C.used))
    for F in range(m):
        if H.used[F][1] != C.used[F][2] or C.used[F][1] != H.used[F][2]: bad += 1
    return m, bad, t
for lagmax, loss in ((0, 0.0), (3, 0.0), (6, 0.1), (12, 0.2)):
    for seed in range(3):
        m, bad, t = run(1200, lagmax, loss, seed)
        print("lag<=%2d loss=%.1f seed=%d: %4d frames, %3d wrong inputs, %d steps" % (lagmax, loss, seed, m, bad, t))
