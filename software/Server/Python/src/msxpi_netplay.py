"""MSXPi-native transport for the Konami's Soccer lockstep stub.

One opcode on the MSXPi byte transport (the same place the Ethernet UNAPI opcodes live,
see msxpi_ethglue.eth_handle_opcode):

    MSX -> [C9][FLAGS][13 packet bytes][SUM]       SUM = sum of the 13 bytes mod 256
    Pi  -> [N][N bytes][SUM]                       N = 0 (nothing) or 13 (a game packet)
           [FF][00]                                the session is dead (no news from the peer)
           [A0+STATE][DELAY][DELAY]                status, when FLAGS bit 7 is set

FLAGS: bit 0 forward the packet to the peer, bit 1 return the oldest delivered packet,
bit 6 (re)start the session (handshake), bit 7 return the status instead.

The game packet (seq, len, F, 8 inputs, check tag, check value) is only relayed; sequence
numbers, redundancy, resends and the desync check stay in the MSX stub.  Everything else is
here: the handshake (version check), the round-trip measurement that fixes the input delay
for the match, keep-alive/dead detection, and the delay/loss injection used by the tests.

Peer datagrams: 13 bytes = game packet, 14 bytes = control (type, version, nonce, a, b).

Session (for now from the environment, later set by the lobby):
    MSXPI_NETPLAY            local_port:peer_host:peer_port
    MSXPI_NETPLAY_LAG_MS     one-way delay added to incoming datagrams (default 0)
    MSXPI_NETPLAY_JITTER_MS  extra random 0..N ms per datagram (default 0)
    MSXPI_NETPLAY_LOSS_PCT   incoming datagrams dropped, percent (default 0)
    MSXPI_NETPLAY_SEED       random seed for the above
    MSXPI_NETPLAY_VERSION    protocol version announced (default 1; tests use it to force a mismatch)
"""
import collections
import heapq
import os
import random
import socket
import struct
import threading
import time

OP_NETPLAY = 0xC9
PKT = 13
CTL = struct.Struct("<BBIII")           # type, version, nonce, a, b  = 14 bytes
VERSION = 1

T_HELLO, T_PING, T_PONG, T_SETUP, T_ACK = 1, 2, 3, 4, 5

# MSX-visible status codes
ST_CONNECTING, ST_READY, ST_VERSION, ST_FAILED = 0, 1, 2, 3
# internal states
S_IDLE, S_CONNECT, S_SETUP, S_READY, S_VERSION, S_FAILED, S_DEAD = range(7)

FRAME_MS = 20.0                        # 50 Hz: the longest frame
PINGS = 8
MIN_SAMPLES = 4
MAX_PINGS = 64
CONNECT_TIMEOUT = 300.0
DEAD_AFTER = 15.0
MIN_DELAY, MAX_DELAY = 2, 6


def choose_delay(rtts):
    """Input delay in frames from measured round trips (seconds)."""
    s = sorted(rtts)
    rtt = s[int(0.9 * (len(s) - 1))]
    d = int(-(-(rtt * 1000.0 / 2) // FRAME_MS)) + 2   # ceil(one-way / frame) + 2
    return max(MIN_DELAY, min(MAX_DELAY, d))


class Netplay:
    def __init__(self, read, write, env=os.environ, log=print):
        """read() -> int|None for one byte from the MSX; write(bytes) -> None."""
        self.read, self.write, self.log = read, write, log
        spec = env.get("MSXPI_NETPLAY", "")
        self.lag = float(env.get("MSXPI_NETPLAY_LAG_MS", "0")) / 1000.0
        self.jitter = float(env.get("MSXPI_NETPLAY_JITTER_MS", "0")) / 1000.0
        self.loss = float(env.get("MSXPI_NETPLAY_LOSS_PCT", "0"))
        self.version = int(env.get("MSXPI_NETPLAY_VERSION", str(VERSION)))
        self.rng = random.Random(int(env.get("MSXPI_NETPLAY_SEED", "1985")))
        self.lock = threading.RLock()
        self.heap = []                    # (release_time, n, datagram)
        self.n = 0
        self.ready = collections.deque()  # game packets released, in order
        self.sock = None
        self.peer = None
        self.state = S_IDLE
        self.delay = 0
        self.stats = dict(tx=0, rx=0, dropped=0, badsum=0, delivered=0)
        self.last_log = 0.0
        self._reset_session()
        if spec:
            lport, host, pport = spec.split(":")
            self.peer = (host, int(pport))
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.bind(("0.0.0.0", int(lport)))
            threading.Thread(target=self._rx_loop, daemon=True).start()
            threading.Thread(target=self._timer_loop, daemon=True).start()
            log("netplay: local %s peer %s lag=%.0fms jitter=%.0fms loss=%.1f%% version=%d"
                % (lport, self.peer, self.lag * 1000, self.jitter * 1000, self.loss, self.version))
        else:
            log("netplay: MSXPI_NETPLAY not set - packets are discarded")

    # ---- session state -------------------------------------------------------------
    def _reset_session(self):
        self.nonce = int.from_bytes(os.urandom(4), 'little') or 1   # not self.rng: it is seeded identically on both sides
        self.peer_nonce = None
        self.leader = False
        self.pings_sent = 0
        self.ping_t = {}
        self.rtts = []
        self.next_ping = 0.0
        self.next_hello = 0.0
        self.next_setup = 0.0
        self.t_start = time.monotonic()
        self.last_rx = self.t_start
        self.delay = 0
        self.ready.clear()

    def restart(self):
        with self.lock:
            self._reset_session()
            self.state = S_CONNECT if self.sock else S_FAILED
            self.log("netplay: session restart nonce=%08x" % self.nonce)

    def _send_ctl(self, typ, a=0, b=0):
        if self.sock:
            try:
                self.sock.sendto(CTL.pack(typ, self.version, self.nonce, a, b), self.peer)
            except OSError:
                pass

    # ---- network threads -----------------------------------------------------------
    def _rx_loop(self):
        while True:
            try:
                data, _ = self.sock.recvfrom(64)
            except OSError:
                if self.sock.fileno() == -1:
                    return                # closed
                continue                  # e.g. Windows ConnectionResetError after an ICMP
                                          # 'port unreachable' for a peer that is not up yet
            if len(data) not in (PKT, CTL.size):
                continue
            self.stats["rx"] += 1
            if self.loss and self.rng.random() * 100 < self.loss:
                self.stats["dropped"] += 1
                continue
            t = time.monotonic() + self.lag + (self.rng.random() * self.jitter)
            with self.lock:
                self.n += 1
                heapq.heappush(self.heap, (t, self.n, data))

    def _timer_loop(self):
        while True:
            time.sleep(0.005)
            with self.lock:
                self._pump(time.monotonic())

    def _pump(self, now):
        while self.heap and self.heap[0][0] <= now:
            _, _, data = heapq.heappop(self.heap)
            if len(data) == CTL.size:
                self._on_ctl(now, *CTL.unpack(data))
            else:
                self._on_game(now, data)
        st = self.state
        if st in (S_CONNECT, S_SETUP):
            if now - self.t_start > CONNECT_TIMEOUT:
                self.state = S_FAILED
                self.log("netplay: connect timed out")
                return
            if now >= self.next_hello and st == S_CONNECT:
                self.next_hello = now + 0.2
                self._send_ctl(T_HELLO)
            if self.leader and st == S_CONNECT and now >= self.next_ping and (
                    self.pings_sent < PINGS or (len(self.rtts) < MIN_SAMPLES and self.pings_sent < MAX_PINGS)):
                self.next_ping = now + 0.1      # keep pinging while too few answers came back
                self.ping_t[self.pings_sent] = now
                self._send_ctl(T_PING, self.pings_sent)
                self.pings_sent += 1
            if self.leader and st == S_CONNECT and len(self.rtts) >= MIN_SAMPLES and (
                    len(self.rtts) >= PINGS or now - self.next_ping > 1.0):
                self.delay = int(os.environ.get('MSXPI_NETPLAY_DELAY', '0')) or choose_delay(self.rtts)
                self.state = S_SETUP
                self.log("netplay: leader, rtt samples %s -> delay %d"
                         % (["%.0f" % (r * 1000) for r in self.rtts], self.delay))
            if self.state == S_SETUP and now >= self.next_setup:
                self.next_setup = now + 0.2
                self._send_ctl(T_SETUP, self.delay)
        elif st == S_READY and now - self.last_rx > DEAD_AFTER:
            self.state = S_DEAD
            self.log("netplay: no news from the opponent for %.0f s - session dead" % DEAD_AFTER)

    def _on_ctl(self, now, typ, ver, nonce, a, b):
        if self.state == S_IDLE:
            if typ == T_PING:             # still answer pings: the peer may be ahead of us
                self._send_ctl(T_PONG, a)
            return
        if ver != self.version:
            if self.state in (S_CONNECT, S_SETUP):
                self.state = S_VERSION
                self.log("netplay: version mismatch (peer %d, ours %d)" % (ver, self.version))
            if self.state == S_VERSION and typ == T_HELLO:
                self._send_ctl(T_HELLO)   # let a peer that started later see the mismatch too
            return
        self.last_rx = now
        if typ == T_HELLO:
            if self.state == S_CONNECT and self.peer_nonce is None:
                self.peer_nonce = nonce
                if nonce == self.nonce:
                    self.nonce = int.from_bytes(os.urandom(4), 'little') or 1
                    self.peer_nonce = None
                else:
                    self.leader = self.nonce > nonce
        elif typ == T_PING:
            self._send_ctl(T_PONG, a)
        elif typ == T_PONG:
            t0 = self.ping_t.pop(a, None)
            if t0 is not None and self.state == S_CONNECT:
                self.rtts.append(now - t0)
        elif typ == T_SETUP:
            if self.state in (S_CONNECT, S_READY):
                self.delay = a
                self.state = S_READY
            self._send_ctl(T_ACK, a)
        elif typ == T_ACK:
            if self.state == S_SETUP and a == self.delay:
                self.state = S_READY
                self.log("netplay: ready, delay %d" % self.delay)

    def _on_game(self, now, data):
        if self.state == S_SETUP:         # the follower started playing: that is the ACK
            self.state = S_READY
            self.log("netplay: ready, delay %d (implicit ack)" % self.delay)
        if self.state == S_READY:
            self.last_rx = now
            self.ready.append(data)

    # ---- one MSX transaction -------------------------------------------------------
    def handle(self, opcode):
        flags = self.read()
        if flags is None:
            return True
        pkt = bytearray()
        for _ in range(PKT):
            b = self.read()
            if b is None:
                return True
            pkt.append(b)
        s = self.read()
        if s is None:
            return True
        if (sum(pkt) & 0xFF) != s:
            self.stats["badsum"] += 1
            flags &= 0x80                 # corrupted: treat the packet part as lost
        if flags & 0x40:
            self.restart()
        with self.lock:
            now = time.monotonic()
            if self.sock:
                self._pump(now)
            if flags & 0x80:
                code = {S_READY: ST_READY, S_VERSION: ST_VERSION,
                        S_FAILED: ST_FAILED, S_DEAD: ST_FAILED}.get(self.state, ST_CONNECTING)
                d = self.delay if code == ST_READY else 0
                if code != getattr(self, '_last_code', None):
                    self._last_code = code
                    self.log('netplay: status -> %d delay %d (state %d)' % (code, d, self.state))
                self.write(bytes([0xA0 + code, d, d]))
                return True
            if flags & 1 and self.sock and self.state == S_READY:
                try:
                    self.sock.sendto(bytes(pkt), self.peer)
                    self.stats["tx"] += 1
                except OSError:
                    pass
            if flags & 2 and self.state in (S_DEAD, S_FAILED):
                self.write(b"\xff\x00")
                return True
            out = self.ready.popleft() if (flags & 2 and self.ready) else b""
        if out:
            self.stats["delivered"] += 1
            self.write(bytes([PKT]) + out + bytes([sum(out) & 0xFF]))
        else:
            self.write(b"\x00\x00")
        now = time.monotonic()
        if now - self.last_log > 10:
            self.last_log = now
            self.log("netplay: %s state=%d" % (self.stats, self.state))
        return True
