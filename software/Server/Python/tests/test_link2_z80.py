"""T3: the assembled MSX LINK2 code against the Python reference model, byte for byte.

The same server steps run once with link2_sim.ModelMsx and once with the Z80 code
(z80_msx.Z80Msx) over the lockstep wire.  Every byte that crosses the wire, in both
directions and in order, must be identical, and so must the outcome (the data, or
that the MSX gave up).  That covers the cases of design section 8 as the server
drives them: clean transfers in both directions, burst and polled, single-block and
multi-block, bit flips and slips at chosen positions (NAK, ABORT, duplicates, the
doubled final answer, the end mark, the ABORT flood).

    python -m unittest test_link2_z80          (about 5 minutes)
"""
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import link2_sim as S
import msxpi_blocks as B
import z80_msx
from test_link2 import pattern


def trace(cls, direction, data, size=8192, has_wait=True, pi_burst=True, may_burst=True,
          flips=(), slips=(), follow=True):
    """(wire log, outcome) of one transfer (and a clean follow-up) with the given MSX."""
    w = S.Wire(timeout=2.0)
    w.trace = True
    for d, i, mask in flips:
        w.flip(d, i, mask)
    for k in slips:
        w.slip(k)
    results = []
    if direction == "msx2pi":
        def loop():
            while True:
                results.append(B.link_recv(65536))
        steps = [loop]
    else:
        def follow_loop():
            while True:
                results.append(B.link_send(pattern(300, 99)))
        steps = [lambda: results.append(B.link_send(data) if data else None), follow_loop]
    srv = S.Server(w, steps, pi_burst).start()
    m = cls(w, size, has_wait)
    outcome = []
    for payload in ([data] + ([pattern(300, 99)] if follow else [])):
        try:
            if direction == "msx2pi":
                m.send(payload, may_burst)
                outcome.append("sent")
            else:
                outcome.append(bytes(m.recv(may_burst=may_burst)))
        except S.MsxAborted:
            outcome.append("aborted")
        except S.Hung:
            outcome.append("hung")  # the lockstep wire ran dry: the server had nothing more to say
    w.close()
    srv.join(2)
    return list(w.log), outcome


class ByteForByte(unittest.TestCase):
    def same(self, *a, **k):
        ref = trace(S.ModelMsx, *a, **k)
        z80 = trace(z80_msx.Z80Msx, *a, **k)
        if ref != z80:
            n = next((i for i, (x, y) in enumerate(zip(ref[0], z80[0])) if x != y), min(len(ref[0]), len(z80[0])))
            self.fail(f"{a} {k}: wire differs at transfer {n}: model {ref[0][max(0, n - 3):n + 4]} "
                      f"z80 {z80[0][max(0, n - 3):n + 4]}; outcomes {ref[1] == z80[1]}")

    def test_clean(self):
        for n in (1, 255, 256, 300, 512, 513, 1024, 8192, 8193, 20000):
            for has_wait in (True, False):
                for pi_burst in (True, False):
                    for direction in ("msx2pi", "pi2msx"):
                        self.same(direction, pattern(n, n), 8192, has_wait, pi_burst, follow=False)

    def test_small_blocks_and_page1(self):
        for direction in ("msx2pi", "pi2msx"):
            self.same(direction, pattern(5000, 3), 512, follow=False)
            self.same(direction, pattern(5000, 3), 600, follow=False)
            self.same(direction, pattern(2048, 4), 1024, may_burst=False, follow=False)
        self.same("msx2pi", b"", 8192, follow=False)

    def test_flips(self):
        r = random.Random(7)
        for direction in ("msx2pi", "pi2msx"):
            for n, size in ((300, 8192), (512, 8192), (700, 256)):
                data = pattern(n, n)
                for _ in range(40):
                    d = r.choice(("p2m", "m2p"))
                    i = r.randrange(n + 40)
                    self.same(direction, data, size, flips=[(d, i, 1 << r.randrange(8))])

    def test_slips(self):
        r = random.Random(8)
        for direction in ("msx2pi", "pi2msx"):
            for n, size in ((300, 8192), (600, 256)):
                for k in r.sample(range(n + 40), 30):
                    self.same(direction, pattern(n, n), size, slips=[k])

    def test_header_and_answer_damage(self):
        """Damage at the first bytes of every block and of the opening: the frames themselves."""
        for direction in ("msx2pi", "pi2msx"):
            for i in range(0, 24):
                for d in ("p2m", "m2p"):
                    self.same(direction, pattern(520, 1), 256, flips=[(d, i, 0x80)])


if __name__ == "__main__":
    unittest.main()
