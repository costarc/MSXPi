"""T1: LINK2 server protocol on the simulated link (no MSX needed)."""
import os, sys, random, unittest

sys.path.insert(0, os.path.dirname(__file__))
import link2_sim as S
import msxpi_const as C
import msxpi_blocks as B


def pattern(n, seed=1):
    r = random.Random(seed)
    return bytes(r.randrange(256) for _ in range(n))


def msx_sends(data, wire=None, size=8192, has_wait=True, pi_burst=True, may_burst=True):
    """MSX -> Pi. Returns (msx exception or None, server result)."""
    w = wire or S.Wire()
    srv = S.Server(w, [lambda: B.link_recv(65536)], pi_burst).start()
    m = S.Msx(w, size, has_wait)
    err = None
    try:
        m.send(data, may_burst)
    except S.MsxAborted as e:
        err = e
    ok = srv.join()
    w.close()
    return err, (srv.results[0] if srv.results else None), ok, srv.error


def pi_sends(data, wire=None, size=8192, has_wait=True, pi_burst=True, may_burst=True):
    w = wire or S.Wire()
    srv = S.Server(w, [lambda: B.link_send(data)], pi_burst).start()
    m = S.Msx(w, size, has_wait)
    err = None
    got = None
    try:
        got = m.recv(may_burst=may_burst)
    except S.MsxAborted as e:
        err = e
    ok = srv.join()
    w.close()
    return err, got, srv.results[0] if srv.results else None, ok, srv.error


SIZES = [0, 1, 255, 256, 512, 513, 8192, 8193, 20000]


def block(seq, payload, good=True, end=None):
    """The MSX's side of one block as link2_recv_block reads it: header, payload,
    and crc + end mark.  good=False damages the CRC; end= overrides the end mark."""
    h = bytes((C.RC_READY, len(payload) & 0xFF, len(payload) >> 8, seq))
    hc = S.crc(h)
    pc = S.crc(payload) ^ (0 if good else 1)
    e = (seq ^ 0xFF) if end is None else end
    return [h + bytes((hc & 0xFF, hc >> 8)), payload, bytes((pc & 0xFF, pc >> 8, e))]


class Scripted:
    """Plays back the MSX's side of read_payload; records the answers."""

    def __init__(self, reads):
        self.reads, self.out = list(reads), []

    def read_payload(self, n):
        b = self.reads.pop(0)
        assert len(b) == n, (len(b), n)
        return C.RC_SUCCESS, b

    def byte_out(self, b):
        self.out.append(b)
        return C.RC_SUCCESS

    def recv_block(self, last_seq=None, next_seq=0, size=512):
        import msxpi_link2 as L
        saved, L.io = L.io, self
        try:
            tr = L.Transfer(size, False)
            tr.last_seq, tr.next_seq = last_seq, next_seq
            return L.link2_recv_block(tr, size)
        finally:
            L.io = saved


class Clean(unittest.TestCase):
    def test_msx_to_pi(self):
        for n in SIZES:
            for has_wait in (True, False):
                for pi_burst in (True, False):
                    d = pattern(n, n)
                    err, res, ok, srverr = msx_sends(d, has_wait=has_wait, pi_burst=pi_burst)
                    self.assertIsNone(err, (n, has_wait, pi_burst))
                    self.assertTrue(ok and srverr is None, (n, srverr))
                    self.assertEqual(res, (C.RC_SUCCESS, d), (n, has_wait, pi_burst))

    def test_pi_to_msx(self):
        for n in SIZES:
            if n == 0:
                continue  # link_send refuses empty payloads (legacy rule)
            for has_wait in (True, False):
                for pi_burst in (True, False):
                    d = pattern(n, n + 7)
                    err, got, res, ok, srverr = pi_sends(d, has_wait=has_wait, pi_burst=pi_burst)
                    self.assertIsNone(err, (n, has_wait, pi_burst))
                    self.assertEqual(got, d, (n, has_wait, pi_burst))
                    self.assertEqual(res, C.RC_SUCCESS)

    def test_small_msx_blocks(self):
        d = pattern(5000, 3)
        err, res, ok, _ = msx_sends(d, size=512)
        self.assertEqual(res, (C.RC_SUCCESS, d))
        err, got, res, ok, _ = pi_sends(d, size=512)
        self.assertEqual(got, d)


class Faults(unittest.TestCase):
    def test_single_bit_everywhere(self):
        import link2_faults as F
        for direction in ("msx2pi", "pi2msx"):
            for n, size in ((300, 8192), (512, 8192), (600, 256)):
                tally, bad = F.sweep(direction, pattern(n, n), size)
                self.assertEqual(dict(tally), {"OK": sum(tally.values())}, (direction, n, bad[:5]))

    def test_slip_everywhere(self):
        """One MSX transfer that the Pi never sees, at every position, both ways:
        always a reported abort or success, never a hang, and the next command
        works within three tries.  (600 bytes in 256-byte blocks: the full sweep
        in link2_faults.py also runs 512 in one block, where one misaligned
        block matches its CRC by chance - design 3.7, known limit.)"""
        import link2_faults as F
        for direction in ("msx2pi", "pi2msx"):
            tally, bad = F.sweep_slip(direction, pattern(600, 600), 256)
            self.assertEqual(bad, [], (direction, dict(tally)))

    def test_no_wait_msx(self):
        import link2_faults as F
        tally, bad = F.sweep("pi2msx", pattern(512, 5), 8192, has_wait=False)
        self.assertEqual(list(tally), ["OK"], bad[:5])

    def test_random_multibit(self):
        """Faults of up to 3 bits per byte, at rates that hit most blocks: nothing
        may land wrong, and nothing may hang.  LINK2_SLOW=1 runs the test plan's
        10,000 transfers (about 17 minutes); the default is 300."""
        import random as R
        verdicts = {"OK": 0, "ABORT": 0, "CORRUPT": 0, "HUNG": 0}
        seeds = 5000 if os.environ.get("LINK2_SLOW") == "1" else 150  # x2 directions
        rates = (1e-3, 3e-3, 1e-2)
        for seed in range(seeds):
            r = R.Random(seed)
            rate = rates[seed % len(rates)]
            data = pattern(r.choice([100, 512, 1500, 3000]), seed)

            def hook(d, i, b):
                if r.random() < rate:
                    for _ in range(r.randint(1, 3)):
                        b ^= 1 << r.randrange(8)
                return b

            for direction in ("msx2pi", "pi2msx"):
                w = S.Wire(timeout=1.0)
                w.hook = hook
                results = []

                def idle():
                    # afterwards the server waits for commands, as the real one
                    # does, instead of leaving the MSX talking to nobody
                    while True:
                        results.append(B.link_recv(65536))

                if direction == "msx2pi":
                    srv = S.Server(w, [idle]).start()
                else:
                    srv = S.Server(w, [lambda: B.link_send(data), idle]).start()
                m = S.Msx(w, 1024)
                got = res = None
                try:
                    if direction == "msx2pi":
                        m.send(data)
                    else:
                        got = m.recv()
                    verdict = "OK"
                except S.MsxAborted:
                    verdict = "ABORT"
                except S.Hung:
                    verdict = "HUNG"
                w.close()
                srv.join(2)
                accepted = [x[1] for x in results if x and x[0] == C.RC_SUCCESS]
                if any(x != data for x in accepted):
                    verdict = "CORRUPT"  # anything the server took must be the data
                if direction == "pi2msx" and got is not None and got != data:
                    verdict = "CORRUPT"
                verdicts[verdict] += 1
        self.assertEqual(verdicts["CORRUPT"], 0, verdicts)
        self.assertEqual(verdicts["HUNG"], 0, verdicts)
        self.assertGreater(verdicts["OK"], 100, verdicts)


class Limits(unittest.TestCase):
    def test_receiver_aborts_after_retries(self):
        """Every header damaged: the server NAKs LINK2_RETRIES times, then ABORTs."""
        w = S.Wire(timeout=2.0)
        # corrupt the first payload byte of every attempt at the header CRC
        w.hook = lambda d, i, b: b ^ 0x10 if d == "m2p" and 8 <= i < 8 + 200 and (i - 8) % 7 == 4 else b
        srv = S.Server(w, [lambda: B.link_recv(65536)]).start()
        m = S.Msx(w, 8192)
        with self.assertRaises(S.MsxAborted) as cm:
            m.send(pattern(64))
        m.wr(C.HELLO2)  # the next command: the server stops answering ABORT
        srv.join(2)
        w.close()
        if S.Msx is S.ModelMsx:  # the Z80 code only reports RC_PROTOERR
            self.assertIn("abort", str(cm.exception))
        self.assertEqual(srv.results[0][0], C.RC_PROTOERR)

    def test_sender_cap_when_receiver_gone(self):
        w = S.Wire(timeout=2.0)

        def deaf():
            # a receiver that never answers anything but 0x00
            for _ in range(2000):
                w.pi_xfer(0)

        srv = S.Server(w, [deaf]).start()
        m = S.Msx(w, 8192)
        m.wr(0)  # keep lockstep: the model opens by hand below
        tr_open = None
        with self.assertRaises(S.MsxAborted):
            m.send(pattern(32))  # never gets HELLO2_ACK: gives up after 16 tries
        w.close()

    def test_overflow_is_aborted(self):
        """More than the server's buffer: the block that does not fit is ABORTed in
        its header slot, so the MSX does not think the transfer succeeded."""
        w = S.Wire(timeout=2.0)
        srv = S.Server(w, [lambda: B.link_recv(600)]).start()
        m = S.Msx(w, 512)
        with self.assertRaises(S.MsxAborted) as cm:
            m.send(pattern(1024))
        m.wr(C.HELLO2)  # the next command: the server stops answering ABORT
        srv.join(2)
        w.close()
        if S.Msx is S.ModelMsx:  # the Z80 code only reports RC_PROTOERR
            self.assertIn("header", str(cm.exception))
        self.assertEqual(srv.results[0][0], C.RC_BUFOVFLW)

    def test_nak_limit_resets_after_duplicate(self):
        """The receiver's limit is per block: NAKs spent on a duplicate do not count
        against the block after it."""
        p0, p1 = pattern(64, 1), pattern(64, 2)
        reads = []
        for _ in range(5):
            reads += block(0, p0, good=False)  # the duplicate of block 0, damaged five times
        reads += block(0, p0)                  # ... then good: re-ACKed and discarded
        for _ in range(C.LINK2_RETRIES - 1):
            reads += block(1, p1, good=False)  # block 1 needs the most NAKs a block may get
        reads += block(1, p1)
        io = Scripted(reads)
        rc, typ, payload = io.recv_block(last_seq=0, next_seq=1)  # block 0's ACK was lost
        self.assertEqual((rc, payload), (C.RC_SUCCESS, p1))
        self.assertNotIn(C.LINK_ABORT, io.out)

    def test_end_mark_checked(self):
        """A block whose CRC is right but whose end mark is not - a misaligned
        block that matched its CRC by chance - is NAKed, then the good one taken."""
        p = pattern(64, 5)
        io = Scripted(block(0, p, end=0x00) + block(0, p))
        rc, typ, payload = io.recv_block()
        self.assertEqual((rc, payload), (C.RC_SUCCESS, p))
        self.assertEqual(io.out, [C.LINK_ACK, C.LINK_NAK, C.LINK_ACK, C.LINK_ACK])

    def test_old_server_gets_protoerr(self):
        w = S.Wire(timeout=2.0)

        def old_server():
            # the shipped server: hunts for READY, ignores everything else
            for _ in range(500):
                w.pi_xfer(0)

        srv = S.Server(w, [old_server]).start()
        m = S.Msx(w, 8192)
        with self.assertRaises(S.MsxAborted) as cm:
            m.send(pattern(32))
        w.close()
        if S.Msx is S.ModelMsx:  # the Z80 code only reports RC_PROTOERR
            self.assertIn("does not speak LINK2", str(cm.exception))


class Mixed(unittest.TestCase):
    def test_legacy_and_link2_alternate(self):
        w = S.Wire(timeout=3.0)
        d = [pattern(700, 1), pattern(900, 2), pattern(10, 3), pattern(1500, 4)]
        steps = [lambda i=i: B.link_recv(65536) for i in range(4)]
        srv = S.Server(w, steps).start()
        leg, l2 = S.LegacyMsx(w, 512), S.Msx(w, 1024)
        leg.send(d[0])
        l2.send(d[1])
        leg.send(d[2])
        l2.send(d[3])
        srv.join(5)
        w.close()
        self.assertEqual([r for r in srv.results], [(C.RC_SUCCESS, x) for x in d])


if __name__ == "__main__":
    unittest.main()
