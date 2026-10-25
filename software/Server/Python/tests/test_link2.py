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
                continue  # sendmultiblock refuses empty payloads (legacy rule)
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

    def test_no_wait_msx(self):
        import link2_faults as F
        tally, bad = F.sweep("pi2msx", pattern(512, 5), 8192, has_wait=False)
        self.assertEqual(list(tally), ["OK"], bad[:5])

    def test_random_multibit(self):
        """Faults of up to 3 bits per byte, at a rate that hits most blocks: nothing
        may land wrong, and nothing may hang."""
        import random as R
        verdicts = {"OK": 0, "ABORT": 0, "CORRUPT": 0, "HUNG": 0}
        for seed in range(150):
            r = R.Random(seed)
            rate = (3e-3, 1e-2)[seed % 2]
            data = pattern(r.choice([100, 512, 1500, 3000]), seed)

            def hook(d, i, b):
                if r.random() < rate:
                    for _ in range(r.randint(1, 3)):
                        b ^= 1 << r.randrange(8)
                return b

            for direction in ("msx2pi", "pi2msx"):
                w = S.Wire(timeout=1.0)
                w.hook = hook
                if direction == "msx2pi":
                    srv = S.Server(w, [lambda: B.link_recv(65536)]).start()
                else:
                    srv = S.Server(w, [lambda: B.link_send(data)]).start()
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
                srv.join(2)
                w.close()
                if direction == "msx2pi" and srv.results and srv.results[0][0] == C.RC_SUCCESS:
                    if srv.results[0][1] != data:
                        verdict = "CORRUPT"
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
        srv.join(2)
        w.close()
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
