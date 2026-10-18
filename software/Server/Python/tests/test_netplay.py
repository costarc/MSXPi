"""msxpi_netplay: handshake, delay negotiation, relay, checksums, dead-peer detection.

Two Netplay sessions talk over loopback UDP; the MSX side is simulated by feeding the bytes of
a transaction to handle() and reading back what it writes.  No emulator needed.
"""
import socket
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_netplay as n


def free_ports(count):
    socks = [socket.socket(socket.AF_INET, socket.SOCK_DGRAM) for _ in range(count)]
    for s in socks:
        s.bind(('127.0.0.1', 0))
    ports = [s.getsockname()[1] for s in socks]
    for s in socks:
        s.close()
    return ports


def make_pair(**env_b):
    pa, pb = free_ports(2)
    ea = {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pa, pb), 'MSXPI_NETPLAY_SEED': '1'}
    eb = {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pb, pa), 'MSXPI_NETPLAY_SEED': '2'}
    eb.update(env_b)
    quiet = lambda *a: None
    return n.Netplay(None, None, ea, quiet), n.Netplay(None, None, eb, quiet)


def wait_for(cond, seconds=10.0):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.01)
    return False


def txn(np, flags, pkt=b'\x00' * n.PKT):
    """One MSX transaction: returns the bytes the Pi wrote back."""
    sent = bytearray([flags]) + pkt + bytes([sum(pkt) & 0xFF])
    it = iter(sent)
    out = []
    np.read = lambda: next(it, None)
    np.write = out.append
    np.handle(n.OP_NETPLAY)
    return bytes(out[0]) if out else b''


def packet(first):
    return bytes([first]) + bytes(range(1, n.PKT))


class Delay(unittest.TestCase):
    def test_choose_delay(self):
        self.assertEqual(n.choose_delay([0.001] * 8), 3)       # localhost
        self.assertEqual(n.choose_delay([0.125] * 8), 6)       # 125 ms round trip, clamped
        self.assertEqual(n.choose_delay([0.040] * 8), 3)
        self.assertEqual(n.choose_delay([2.0] * 8), n.MAX_DELAY)

    def test_outlier_is_ignored_by_the_percentile(self):
        rtts = [0.001] * 7 + [0.5]
        self.assertEqual(n.choose_delay(rtts), 3)


class Session(unittest.TestCase):
    def tearDown(self):
        for s in getattr(self, 'pair', ()):
            s.sock.close()

    def start(self, **env_b):
        self.a, self.b = self.pair = make_pair(**env_b)
        self.a.restart()
        self.b.restart()

    def test_handshake_agrees_on_delay(self):
        self.start()
        self.assertTrue(wait_for(lambda: self.a.state == n.S_READY and self.b.state == n.S_READY))
        self.assertEqual(self.a.delay, self.b.delay)
        self.assertGreaterEqual(self.a.delay, n.MIN_DELAY)
        self.assertLessEqual(self.a.delay, n.MAX_DELAY)

    def test_same_seed_still_elects_a_leader(self):
        pa, pb = free_ports(2)
        quiet = lambda *a: None
        env = lambda l, p: {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (l, p)}      # default seed on both sides
        a = n.Netplay(None, None, env(pa, pb), quiet)
        b = n.Netplay(None, None, env(pb, pa), quiet)
        self.pair = (a, b)
        a.restart()
        b.restart()
        self.assertTrue(wait_for(lambda: a.state == n.S_READY and b.state == n.S_READY))
        self.assertNotEqual(a.leader, b.leader)

    def test_peer_that_starts_late(self):
        # HELLOs sent to a closed port come back as 'port unreachable' (ConnectionResetError on
        # Windows): the receive loop must survive that
        pa, pb = free_ports(2)
        quiet = lambda *a: None
        a = n.Netplay(None, None, {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pa, pb)}, quiet)
        self.pair = (a,)
        a.restart()
        time.sleep(1.0)
        b = n.Netplay(None, None, {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pb, pa)}, quiet)
        self.pair = (a, b)
        b.restart()
        self.assertTrue(wait_for(lambda: a.state == n.S_READY and b.state == n.S_READY))

    def test_lag_raises_the_delay(self):
        pa, pb = free_ports(2)
        env = lambda l, p, seed: {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (l, p), 'MSXPI_NETPLAY_SEED': seed,
                                  'MSXPI_NETPLAY_LAG_MS': '50'}
        quiet = lambda *a: None
        a = n.Netplay(None, None, env(pa, pb, '1'), quiet)
        b = n.Netplay(None, None, env(pb, pa, '2'), quiet)
        self.pair = (a, b)
        a.restart()
        b.restart()
        self.assertTrue(wait_for(lambda: a.state == n.S_READY and b.state == n.S_READY))
        self.assertEqual(a.delay, 5)                            # 100 ms round trip -> 50 ms one way -> 3 + 2
        self.assertEqual(b.delay, 5)

    def test_version_mismatch_stops_both(self):
        self.start(MSXPI_NETPLAY_VERSION='2')
        self.assertTrue(wait_for(lambda: self.a.state == n.S_VERSION and self.b.state == n.S_VERSION))
        self.assertEqual(txn(self.a, 0x80)[0], 0xA0 + n.ST_VERSION)

    def test_late_peer_still_learns_about_a_mismatch(self):
        pa, pb = free_ports(2)
        quiet = lambda *a: None
        a = n.Netplay(None, None, {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pa, pb)}, quiet)
        b = n.Netplay(None, None, {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pb, pa),
                                   'MSXPI_NETPLAY_VERSION': '2'}, quiet)
        self.pair = (a, b)
        a.restart()
        time.sleep(0.3)
        self.assertEqual(a.state, n.S_CONNECT)
        b.restart()
        self.assertTrue(wait_for(lambda: b.state == n.S_VERSION and a.state == n.S_VERSION))

    def test_status_before_ready(self):
        self.start()
        first = txn(self.a, 0x80)
        self.assertIn(first[0], (0xA0 + n.ST_CONNECTING, 0xA0 + n.ST_READY))
        self.assertTrue(wait_for(lambda: self.a.state == n.S_READY and self.b.state == n.S_READY))
        st = txn(self.a, 0x80)
        self.assertEqual(st[0], 0xA0 + n.ST_READY)
        self.assertEqual(st[1], self.a.delay)
        self.assertEqual(st[2], self.a.delay)


class Relay(unittest.TestCase):
    def setUp(self):
        self.a, self.b = make_pair()
        self.a.restart()
        self.b.restart()
        self.assertTrue(wait_for(lambda: self.a.state == n.S_READY and self.b.state == n.S_READY))

    def tearDown(self):
        self.a.sock.close()
        self.b.sock.close()

    def test_packet_travels_and_is_checksummed(self):
        pkt = packet(7)
        self.assertEqual(txn(self.a, 1, pkt), b'\x00\x00')              # send only: nothing back
        got = b''
        wait_for(lambda: bool(self.b.ready))
        got = txn(self.b, 2)
        self.assertEqual(got[0], n.PKT)
        self.assertEqual(got[1:1 + n.PKT], pkt)
        self.assertEqual(got[-1], sum(pkt) & 0xFF)

    def test_poll_with_nothing_waiting(self):
        self.assertEqual(txn(self.b, 2), b'\x00\x00')

    def test_order_is_kept(self):
        for i in range(1, 6):
            txn(self.a, 1, packet(i))
        wait_for(lambda: len(self.b.ready) == 5)
        firsts = [txn(self.b, 2)[1] for _ in range(5)]
        self.assertEqual(firsts, [1, 2, 3, 4, 5])

    def test_corrupt_transaction_is_dropped(self):
        pkt = packet(9)
        sent = bytearray([1]) + pkt + bytes([(sum(pkt) + 1) & 0xFF])   # wrong sum
        it = iter(sent)
        self.a.read = lambda: next(it, None)
        self.a.write = lambda d: None
        self.a.handle(n.OP_NETPLAY)
        time.sleep(0.2)
        self.assertEqual(self.a.stats['badsum'], 1)
        self.assertFalse(self.b.ready)

    def test_dead_peer(self):
        old = n.DEAD_AFTER
        n.DEAD_AFTER = 0.3
        try:
            self.assertTrue(wait_for(lambda: self.a.state == n.S_DEAD))
            self.assertEqual(txn(self.a, 2), b'\xff\x00')
        finally:
            n.DEAD_AFTER = old

    def test_restart_flushes_old_packets(self):
        txn(self.a, 1, packet(3))
        wait_for(lambda: bool(self.b.ready))
        self.b.restart()
        self.assertFalse(self.b.ready)


class Loss(unittest.TestCase):
    def test_handshake_survives_loss(self):
        pa, pb = free_ports(2)
        quiet = lambda *a: None
        env = lambda l, p, seed: {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (l, p), 'MSXPI_NETPLAY_SEED': seed,
                                  'MSXPI_NETPLAY_LOSS_PCT': '30'}
        a = n.Netplay(None, None, env(pa, pb, '1'), quiet)
        b = n.Netplay(None, None, env(pb, pa, '2'), quiet)
        try:
            a.restart()
            b.restart()
            self.assertTrue(wait_for(lambda: a.state == n.S_READY and b.state == n.S_READY, 20))
            self.assertEqual(a.delay, b.delay)
        finally:
            a.sock.close()
            b.sock.close()


if __name__ == '__main__':
    unittest.main()
