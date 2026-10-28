"""msxpi_netplay: handshake, delay negotiation, relay, checksums, start and dead timeouts, BYE.

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


def make_pair(env_a=None, **env_b):
    pa, pb = free_ports(2)
    ea = {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pa, pb), 'MSXPI_NETPLAY_SEED': '1'}
    eb = {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pb, pa), 'MSXPI_NETPLAY_SEED': '2'}
    ea.update(env_a or {})
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


def txn(np, flags, pkt=b''):
    """One MSX transaction (C9, FLAGS, L, P[L], SUM): returns the bytes the Pi wrote back."""
    sent = bytearray([flags, len(pkt)]) + pkt + bytes([sum(pkt) & 0xFF])
    it = iter(sent)
    out = []
    np.read = lambda: next(it, None)
    np.write = out.append
    np.handle(n.OP_NETPLAY)
    return bytes(out[0]) if out else b''


def packet(seq, width=1):
    """A well-formed game packet: kind, seq, F, W, 8 records (W input bytes and a count), check tag, check value."""
    return bytes([n.KIND_GAME, seq, 0, width]) + bytes((seq + i) & 0xFF for i in range(8 * (width + 1))) + b'\xff\x00'


def stream(count, width=2, first=0):
    """Consecutive game packets as the stub sends them: F = seq = first..first+count-1, each carrying the records of
    frames F-7..F (W input bytes and a count, from the frame number), so each repeats 7 records of the one before."""
    rec = lambda f: bytes(((f * 7 + i) & 0xFF) for i in range(width)) + bytes([f % 3 + 1])
    return [bytes([n.KIND_GAME, f & 0xFF, f & 0xFF, width]) + b''.join(rec(f - 7 + j) for j in range(8))
            + bytes([f & 0xF0, (f * 5) & 0xFF]) for f in range(first, first + count)]


class Deltas(unittest.TestCase):
    def test_a_following_packet_shrinks_to_r_plus_4_bytes(self):
        for width in (1, 2, 4):
            p0, p1 = stream(2, width, first=20)
            d = n.delta_of(p1, p0)
            self.assertEqual(len(d), width + 5)
            self.assertEqual(n.undelta(d, p0), p1)

    def test_a_packet_every_k_frames_carries_k_records(self):
        for width in (1, 2, 4):
            for k in (2, 3):
                p0, *_, pk = stream(k + 1, width, first=250)
                d = n.delta_of(pk, p0)
                self.assertEqual(len(d), k * (width + 1) + 4)
                self.assertLess(len(d), 22)                             # shorter than any full packet
                self.assertEqual(n.undelta(d, p0), pk)

    def test_only_the_next_packets_are_deltas(self):
        p0, p1, p2, p3, p4 = stream(5)
        self.assertIsNone(n.delta_of(p4, p0))                           # F four ahead: more than MAX_K
        self.assertIsNone(n.delta_of(p0, p0))                           # a resend
        self.assertIsNone(n.delta_of(p0, p1))                           # an older window
        self.assertIsNone(n.delta_of(p1, None))
        changed = bytearray(p1)
        changed[5] ^= 1                                                 # an old record that changed
        self.assertIsNone(n.delta_of(bytes(changed), p0))
        self.assertIsNone(n.undelta(n.delta_of(p2, p1), p0))            # applied to the wrong base
        self.assertIsNone(n.undelta(n.delta_of(p1, p0), None))

    def test_wraps_at_frame_255(self):
        p0, p1 = stream(2, first=255)
        self.assertEqual(n.undelta(n.delta_of(p1, p0), p0), p1)


class Delay(unittest.TestCase):
    def test_choose_delay(self):
        self.assertEqual(n.choose_delay([0.001] * 8), 3)       # localhost
        self.assertEqual(n.choose_delay([0.125] * 8), 6)       # 125 ms round trip, clamped
        self.assertEqual(n.choose_delay([0.040] * 8), 3)
        self.assertEqual(n.choose_delay([2.0] * 8), n.MAX_DELAY)

    def test_delay_rule_with_k_and_service(self):
        # ceil(rtt90 / 2 / 20 ms) + 2 + (K - 1) + S, clamped to 2..7
        self.assertEqual(n.choose_delay([0.001] * 8, 2, 0), 4)
        self.assertEqual(n.choose_delay([0.001] * 8, 2, 1), 5)
        self.assertEqual(n.choose_delay([0.001] * 8, 3, 2), 7)
        self.assertEqual(n.choose_delay([0.125] * 8, 3, 1), n.MAX_DELAY)
        self.assertEqual(n.MAX_DELAY, 7)

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

    def test_k_is_the_larger_and_s_the_larger_of_both_sides(self):
        for env_a, env_b in (({'MSXPI_NETPLAY_K': '1'}, {'MSXPI_NETPLAY_K': '2', 'MSXPI_NETPLAY_S': '1'}),
                             ({'MSXPI_NETPLAY_K': '2', 'MSXPI_NETPLAY_S': '1'}, {'MSXPI_NETPLAY_K': '1'})):
            self.pair = make_pair(env_a, **env_b)      # either side may be the leader: seeds differ, so try both
            self.a, self.b = self.pair
            self.a.restart()
            self.b.restart()
            self.assertTrue(wait_for(lambda: self.a.state == n.S_READY and self.b.state == n.S_READY))
            self.assertEqual((self.a.k, self.b.k), (2, 2))
            self.assertEqual(self.a.delay, self.b.delay)
            self.assertEqual(self.a.delay, 5)                   # localhost: 3, + (K - 1) + S
            self.assertEqual(txn(self.a, 0x80)[2], 2)           # the status carries K
            for s in self.pair:
                s.sock.close()

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
        self.start(MSXPI_NETPLAY_VERSION='3')
        self.assertTrue(wait_for(lambda: self.a.state == n.S_VERSION and self.b.state == n.S_VERSION))
        self.assertEqual(txn(self.a, 0x80)[0], 0xA0 + n.ST_VERSION)

    def test_late_peer_still_learns_about_a_mismatch(self):
        pa, pb = free_ports(2)
        quiet = lambda *a: None
        a = n.Netplay(None, None, {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pa, pb)}, quiet)
        b = n.Netplay(None, None, {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pb, pa),
                                   'MSXPI_NETPLAY_VERSION': '3'}, quiet)
        self.pair = (a, b)
        a.restart()
        time.sleep(0.3)
        self.assertEqual(a.state, n.S_CONNECT)
        b.restart()
        self.assertTrue(wait_for(lambda: b.state == n.S_VERSION and a.state == n.S_VERSION))

    def test_different_profiles_stop_both(self):
        pa, pb = free_ports(2)
        quiet = lambda *a: None
        a = n.Netplay(None, None, {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pa, pb), 'MSXPI_NETPLAY_PROFILE': '1234abcd'}, quiet)
        b = n.Netplay(None, None, {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (pb, pa), 'MSXPI_NETPLAY_PROFILE': '1234abce'}, quiet)
        self.pair = (a, b)
        a.restart()
        b.restart()
        self.assertTrue(wait_for(lambda: a.state == n.S_INCOMPATIBLE and b.state == n.S_INCOMPATIBLE))
        self.assertEqual(txn(a, 0x80)[0], 0xA0 + n.ST_INCOMPATIBLE)

    def test_same_profile_connects(self):
        pa, pb = free_ports(2)
        quiet = lambda *a: None
        env = lambda l, p: {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (l, p), 'MSXPI_NETPLAY_PROFILE': '1234abcd'}
        a, b = n.Netplay(None, None, env(pa, pb), quiet), n.Netplay(None, None, env(pb, pa), quiet)
        self.pair = (a, b)
        a.restart()
        b.restart()
        self.assertTrue(wait_for(lambda: a.state == n.S_READY and b.state == n.S_READY))

    def test_status_before_ready(self):
        self.start()
        first = txn(self.a, 0x80)
        self.assertIn(first[0], (0xA0 + n.ST_CONNECTING, 0xA0 + n.ST_READY))
        self.assertTrue(wait_for(lambda: self.a.state == n.S_READY and self.b.state == n.S_READY))
        st = txn(self.a, 0x80)
        self.assertEqual(st[0], 0xA0 + n.ST_READY)
        self.assertEqual(st[1], self.a.delay)
        self.assertEqual(st[2], self.a.k)                  # the third byte is K


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
        self.assertEqual(len(pkt), 22)
        self.assertEqual(txn(self.a, 1, pkt), b'\x00\x00')              # send only: nothing back
        wait_for(lambda: bool(self.b.ready))
        got = txn(self.b, 2)
        self.assertEqual(got, bytes([len(pkt)]) + pkt + bytes([sum(pkt) & 0xFF]))

    def test_four_input_bytes_per_frame(self):
        pkt = packet(5, width=4)
        self.assertEqual(len(pkt), n.MAX_PKT)
        txn(self.a, 1, pkt)
        wait_for(lambda: bool(self.b.ready))
        self.assertEqual(txn(self.b, 2)[1:-1], pkt)

    def test_malformed_packets_are_not_relayed(self):
        bad = [packet(1)[:-1],                                           # length does not match W
               bytes([0x11]) + packet(1)[1:],                            # unknown kind
               bytes([n.KIND_GAME, 1, 0, 5]) + bytes(50)]                # W = 5
        for pkt in bad:
            txn(self.a, 1, pkt)
        time.sleep(0.2)
        self.assertFalse(self.b.ready)
        self.assertEqual(self.a.stats['malformed'], 2)                   # the 54-byte one is over MAX_PKT
        self.assertEqual(self.a.stats['badsum'], 1)
        junk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)          # straight from the opponent's address
        try:
            junk.bind(('127.0.0.1', 0))
            self.b.peer = None
            self.b.peer_ips = {'127.0.0.1'}
            junk.sendto(bytes([0x42]) + bytes(13), ('127.0.0.1', self.b.sock.getsockname()[1]))
            self.assertTrue(wait_for(lambda: self.b.stats['malformed'] == 1, 2))
        finally:
            junk.close()

    def test_delta_from_the_msx_is_relayed_in_full(self):
        p0, p1 = stream(2)
        txn(self.a, 1, p0)
        txn(self.a, 1 | 4, n.delta_of(p1, p0))
        self.assertTrue(wait_for(lambda: len(self.b.ready) == 2))
        self.assertEqual([txn(self.b, 2)[1:-1] for _ in range(2)], [p0, p1])
        self.assertEqual(self.a.stats['deltas_in'], 1)

    def test_delta_without_its_base_is_lost(self):
        p0, p1, p2 = stream(3)
        txn(self.a, 1 | 4, n.delta_of(p1, p0))                          # the Pi never had p0
        txn(self.a, 1, p0)
        txn(self.a, 1 | 4, n.delta_of(p2, p1))                          # its base p1 never arrived
        self.assertTrue(wait_for(lambda: len(self.b.ready) == 1))
        time.sleep(0.2)
        self.assertEqual(len(self.b.ready), 1)
        self.assertEqual(self.a.stats['malformed'], 2)

    def test_replies_are_deltas_only_when_allowed(self):
        packets = stream(4)
        for pkt in packets:
            txn(self.a, 1, pkt)
        self.assertTrue(wait_for(lambda: len(self.b.ready) == 4))
        r0 = txn(self.b, 2 | 8)                                         # no base yet: in full
        r1 = txn(self.b, 2 | 8)
        r2 = txn(self.b, 2)                                             # not allowed: in full
        r3 = txn(self.b, 2 | 8)
        self.assertEqual(r0[1:-1], packets[0])
        self.assertEqual(r1[0], 7)
        self.assertEqual(r1[-1], sum(r1[1:-1]) & 0xFF)
        self.assertEqual(n.undelta(r1[1:-1], packets[0]), packets[1])
        self.assertEqual(r2[1:-1], packets[2])
        self.assertEqual(n.undelta(r3[1:-1], packets[2]), packets[3])
        self.assertEqual(self.b.stats['deltas_out'], 2)

    def test_poll_with_nothing_waiting(self):
        self.assertEqual(txn(self.b, 2), b'\x00\x00')

    def test_order_is_kept(self):
        for i in range(1, 6):
            txn(self.a, 1, packet(i))
        wait_for(lambda: len(self.b.ready) == 5)
        seqs = [txn(self.b, 2)[2] for _ in range(5)]                    # reply: L, kind, seq, ...
        self.assertEqual(seqs, [1, 2, 3, 4, 5])

    def test_corrupt_transaction_is_dropped(self):
        pkt = packet(9)
        sent = bytearray([1, len(pkt)]) + pkt + bytes([(sum(pkt) + 1) & 0xFF])   # wrong sum
        it = iter(sent)
        self.a.read = lambda: next(it, None)
        self.a.write = lambda d: None
        self.a.handle(n.OP_NETPLAY)
        time.sleep(0.2)
        self.assertEqual(self.a.stats['badsum'], 1)
        self.assertFalse(self.b.ready)

    def test_dead_peer_once_playing(self):
        old = n.DEAD_AFTER
        n.DEAD_AFTER = 0.3
        try:
            time.sleep(0.5)
            self.assertEqual(self.a.state, n.S_READY)                    # not playing yet: the start timeout applies
            txn(self.b, 1, packet(1))
            self.assertTrue(wait_for(lambda: self.a.playing))
            self.assertTrue(wait_for(lambda: self.a.state == n.S_DEAD))
            self.assertEqual(txn(self.a, 2), b'\xff\x00')
            self.assertEqual(self.a.describe(), 'connection lost')
        finally:
            n.DEAD_AFTER = old

    def test_opponent_never_starts(self):
        old = n.START_TIMEOUT
        n.START_TIMEOUT = 0.3
        try:
            self.assertTrue(wait_for(lambda: self.a.state == n.S_DEAD))
            self.assertEqual(txn(self.a, 0x80)[0], 0xA0 + n.ST_FAILED)
        finally:
            n.START_TIMEOUT = old

    def test_bye_ends_the_game_on_both_sides(self):
        self.assertEqual(txn(self.a, 0x20, bytes([1])), b'\x00\x00')    # this player pressed the exit key
        self.assertEqual(self.a.state, n.S_ENDED)
        self.assertEqual(self.a.local_result, 1)
        self.assertTrue(wait_for(lambda: self.b.state == n.S_LEFT))
        self.assertEqual(self.b.bye_reason, 1)
        self.assertEqual(txn(self.b, 2), b'\xfe\x01')
        self.assertEqual(txn(self.b, 0x80)[0], 0xA0 + n.ST_LEFT)
        self.assertEqual(self.b.describe(), 'the opponent ended it')
        self.assertTrue(wait_for(lambda: self.a.bye_left == 0, 2))      # sent BYE_REPEAT times

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


class Api(unittest.TestCase):
    """The session API the chat uses: open, candidates, set_peers, close."""

    def tearDown(self):
        for s in getattr(self, 'objs', ()):
            s.close()

    def make(self, count=2):
        quiet = lambda *a: None
        self.objs = [n.Netplay(None, None, {}, quiet) for _ in range(count)]
        return self.objs

    def test_restart_without_configuration_fails_at_once(self):
        a, = self.make(1)
        a.restart()
        self.assertEqual(a.state, n.S_FAILED)
        self.assertFalse(a.configured)

    def test_two_sessions_by_candidates_with_a_dead_one(self):
        a, b = self.make()
        pa, pb = a.open(), b.open()
        dead = free_ports(1)[0]
        a.set_peers([('127.0.0.1', dead), ('127.0.0.1', pb)])       # first candidate goes nowhere
        b.set_peers([('127.0.0.1', pa)])
        self.assertTrue(a.configured)
        a.restart()
        b.restart()
        self.assertTrue(wait_for(lambda: a.state == n.S_READY and b.state == n.S_READY))
        self.assertEqual(a.peer, ('127.0.0.1', pb))                  # locked on the one that answered

    def test_strangers_are_ignored(self):
        a, b = self.make()
        pa, pb = a.open(), b.open()
        a.set_peers([('127.0.0.1', pb)])
        a.restart()
        stranger = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            stranger.bind(('127.0.0.1', 0))
            # same IP, other port: allowed before a peer is locked (NAT may rewrite the port) ...
            a.set_peers([('127.0.0.1', pb)])
            a.peer = ('127.0.0.1', pb)                                # ... but not once it is locked
            stranger.sendto(bytes(n.CTL.size), ('127.0.0.1', pa))
            time.sleep(0.2)
            self.assertEqual(a.stats['rx'], 0)
        finally:
            stranger.close()

    def test_close_frees_the_port(self):
        a, = self.make(1)
        port = a.open()
        a.close()
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            probe.bind(('0.0.0.0', port))
        finally:
            probe.close()
        self.assertEqual(a.state, n.S_IDLE)


class Stun(unittest.TestCase):
    def reply(self, txid, ip, port, xor=True):
        if xor:
            cookie = bytes([0x21, 0x12, 0xA4, 0x42])
            body = bytes([0, 1]) + (port ^ 0x2112).to_bytes(2, 'big') +                 bytes(b ^ c for b, c in zip(socket.inet_aton(ip), cookie))
            attr = (0x0020).to_bytes(2, 'big')
        else:
            body = bytes([0, 1]) + port.to_bytes(2, 'big') + socket.inet_aton(ip)
            attr = (0x0001).to_bytes(2, 'big')
        return (0x0101).to_bytes(2, 'big') + len(body).__add__(4).to_bytes(2, 'big') +             bytes([0x21, 0x12, 0xA4, 0x42]) + txid + attr + len(body).to_bytes(2, 'big') + body

    def test_parse_both_address_kinds(self):
        txid = bytes(range(12))
        self.assertEqual(n.parse_stun(self.reply(txid, '203.0.113.9', 40000), txid), ('203.0.113.9', 40000))
        self.assertEqual(n.parse_stun(self.reply(txid, '203.0.113.9', 40000, xor=False), txid),
                         ('203.0.113.9', 40000))

    def test_parse_rejects_wrong_transaction_and_junk(self):
        txid = bytes(range(12))
        self.assertIsNone(n.parse_stun(self.reply(txid, '1.2.3.4', 5), bytes(12)))
        self.assertIsNone(n.parse_stun(b'short', txid))

    def test_query_against_a_local_server(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        server.bind(('127.0.0.1', 0))
        import threading

        def serve():
            data, addr = server.recvfrom(64)
            server.sendto(self.reply(data[8:20], '198.51.100.7', addr[1]), addr)
        threading.Thread(target=serve, daemon=True).start()
        a = n.Netplay(None, None, {}, lambda *x: None)
        try:
            a.open()
            found = n.stun_query(a.sock, ('127.0.0.1', server.getsockname()[1]), inbox=a.stun_inbox)
            self.assertEqual(found, ('198.51.100.7', a.sock.getsockname()[1]))
            cands = a.candidates(stun=True, stun_server=('127.0.0.1', 9))   # nobody there: LAN only
            self.assertTrue(all(c.endswith(':%d' % a.sock.getsockname()[1]) for c in cands))
        finally:
            a.close()
            server.close()

    def test_query_without_an_answer_gives_up(self):
        a = n.Netplay(None, None, {}, lambda *x: None)
        try:
            a.open()
            self.assertIsNone(n.stun_query(a.sock, ('127.0.0.1', 9), timeout=0.4, inbox=a.stun_inbox))
        finally:
            a.close()


if __name__ == '__main__':
    unittest.main()
