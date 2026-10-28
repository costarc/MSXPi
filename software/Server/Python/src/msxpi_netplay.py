"""PLAYNET's MSXPi transport: the Pi side of a lockstep game's network session.

Specification: documents/PLAYNET-PROTOCOLS.md (the C9 transaction in 10.1, MSXNP in 11).

One opcode on the MSXPi byte transport (the same place the Ethernet UNAPI opcodes live,
see msxpi_ethglue.eth_handle_opcode):

    MSX -> [C9][FLAGS][L][L packet bytes][SUM]      SUM = sum of the L bytes mod 256; L = 0 when nothing is sent
    Pi  -> [L][L bytes][SUM]                        a game packet (L = 22..46)
           [00][00]                                 nothing
           [FF][00]                                 the opponent is gone (no news, or never started)
           [FE][REASON]                             the opponent left (BYE with its result code)
           [A0+STATE][DELAY][DELAY]                 status, when FLAGS bit 7 is set

FLAGS: bit 0 forward the packet to the peer, bit 1 return the oldest delivered packet, bit 2 the packet is a
DELTA, bit 3 the reply may be a DELTA, bit 5 send BYE (L = 1, the packet byte is the result code), bit 6
(re)start the session (handshake), bit 7 return the status instead.  STATE: 0 connecting, 1 ready,
2 incompatible, 3 failed, 4 the opponent left.

DELTA (PLAYNET-PROTOCOLS.md 10.1): consecutive game packets repeat most of their 8 frame records, so on the
MSXPi link a packet that follows the previous one in that direction (same kind and W, F d = 1..MAX_K more, its
first 8 - d records the previous one's last 8 - d) travels as seq, F, the d new records, check tag, check value:
d * R + 4 bytes (R = W + 1; d is K, a packet every K frames).  The Pi rebuilds it from the last packet the MSX
sent, and sends one only when the MSX allows it (bit 3, it holds the last packet the Pi gave it); a reply of
fewer than 22 bytes (the shortest full packet) is a DELTA.

Peer datagrams start with a kind byte: 1-6 = 14-byte control datagram (type, version, nonce, a, b),
10h = game packet of 14 + 8W bytes (W = input bytes per frame, 1-4, in its byte 3; each of its 8 frame records
is W input bytes and an interrupt count).  The game packet is only
relayed; sequence numbers, redundancy, resends and the desync check stay in the MSX stub.  Everything else
is here: the handshake (protocol version and profile hash), the round-trip measurement that fixes the input
delay, the start and dead timeouts, BYE, and the delay/loss injection used by the tests.

Session: normally set by the chat (msxpi_games via msxpi_chat) once both players agreed to a game:
    open(), candidates(), set_peers(), profile_hash - then the MSX side starts it (flags 0x40).  For the test
    rigs it can also come from the environment:
    MSXPI_NETPLAY            local_port:peer_host:peer_port
    MSXPI_NETPLAY_PROFILE    profile hash announced in HELLO, hex (default 0)
    MSXPI_NETPLAY_LAG_MS     one-way delay added to incoming datagrams (default 0)
    MSXPI_NETPLAY_JITTER_MS  extra random 0..N ms per datagram (default 0)
    MSXPI_NETPLAY_LOSS_PCT   incoming datagrams dropped, percent (default 0)
    MSXPI_NETPLAY_SEED       random seed for the above
    MSXPI_NETPLAY_VERSION    MSXNP version announced (default 2 = VERSION; tests use it to force a mismatch)
"""
import collections
import heapq
import os
import queue
import random
import socket
import struct
import threading
import time

OP_NETPLAY = 0xC9
KIND_GAME = 0x10
MIN_WIDTH, MAX_WIDTH = 1, 4             # input bytes per player per frame
MAX_PKT = 14 + 8 * MAX_WIDTH            # 46
CTL = struct.Struct("<BBIII")           # type, version, nonce, a, b  = 14 bytes
VERSION = 2                             # MSXNP (2: K and S in HELLO, K in SETUP; PLAYNET-TCPIP-PERFORMANCE.md 5.3)

T_HELLO, T_PING, T_PONG, T_SETUP, T_ACK, T_BYE = 1, 2, 3, 4, 5, 6

# MSX-visible status codes
ST_CONNECTING, ST_READY, ST_INCOMPATIBLE, ST_FAILED, ST_LEFT = 0, 1, 2, 3, 4
ST_VERSION = ST_INCOMPATIBLE
# internal states
S_IDLE, S_CONNECT, S_SETUP, S_READY, S_INCOMPATIBLE, S_FAILED, S_DEAD, S_LEFT, S_ENDED = range(9)
S_VERSION = S_INCOMPATIBLE

FRAME_MS = 20.0                        # 50 Hz: the longest frame
PINGS = 8
MIN_SAMPLES = 4
MAX_PINGS = 64
CONNECT_TIMEOUT = 120.0                # no READY after this: failed
START_TIMEOUT = 60.0                   # READY but no game packet after this: gone
DEAD_AFTER = 15.0                      # playing, and nothing from the opponent for this long: gone
BYE_REPEAT, BYE_GAP = 3, 0.1
MIN_DELAY, MAX_DELAY = 2, 7
MIN_K, MAX_K = 1, 3                    # send interval, in frames


STUN_SERVER = ("stun.l.google.com", 19302)
STUN_COOKIE = struct.pack(">I", 0x2112A442)


def game_packet_ok(data):
    """True for a well-formed MSXNP game packet (kind, width, length)."""
    return (len(data) >= 4 and data[0] == KIND_GAME and MIN_WIDTH <= data[3] <= MAX_WIDTH
            and len(data) == 14 + 8 * data[3])


def delta_of(new, base):
    """The DELTA of game packet `new` against `base` (seq, F, the d new records, check tag and value), or None
    when `new` does not follow `base` (F 1..MAX_K frames later, the records in between the same)."""
    if not base or len(new) != len(base) or new[0] != base[0] or new[3] != base[3]:
        return None
    d = (new[2] - base[2]) & 0xFF
    r = (len(new) - 6) // 8
    if not MIN_K <= d <= MAX_K or new[4:4 + (8 - d) * r] != base[4 + d * r:4 + 8 * r]:
        return None
    return bytes(new[1:3]) + bytes(new[4 + (8 - d) * r:])


def undelta(delta, base):
    """The game packet a DELTA stands for, from `base` (the previous one), or None when it does not fit."""
    if not base:
        return None
    r = (len(base) - 6) // 8
    d, rest = divmod(len(delta) - 4, r)
    if rest or not MIN_K <= d <= MAX_K or delta[1] != (base[2] + d) & 0xFF:
        return None
    return bytes([base[0], delta[0], delta[1], base[3]]) + bytes(base[4 + d * r:4 + 8 * r]) + bytes(delta[2:])


def lan_address():
    """The address this machine would use to reach the internet (no packet is sent).
    MSXPI_NETPLAY_LAN overrides it (tests on one machine use 127.0.0.1)."""
    if os.environ.get("MSXPI_NETPLAY_LAN"):
        return os.environ["MSXPI_NETPLAY_LAN"]
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("192.0.2.1", 9))
        return probe.getsockname()[0]
    except OSError:
        return None
    finally:
        probe.close()


def stun_query(sock, server, timeout=2.0, inbox=None):
    """Public (ip, port) of `sock` as seen by a STUN server (RFC 5389 binding request), or None.
    With `inbox` (a queue the receive thread fills with STUN replies) the socket may be in use by
    that thread; without it the reply is read from the socket here."""
    txid = os.urandom(12)
    request = struct.pack(">HHI", 0x0001, 0, 0x2112A442) + txid
    try:
        address = socket.gethostbyname(server[0])
    except OSError:
        return None
    old = sock.gettimeout()
    try:
        for _ in range(2):
            sock.sendto(request, (address, server[1]))
            end = time.monotonic() + timeout / 2
            while time.monotonic() < end:
                try:
                    if inbox is not None:
                        data = inbox.get(timeout=max(0.01, end - time.monotonic()))
                    else:
                        sock.settimeout(max(0.01, end - time.monotonic()))
                        data, _ = sock.recvfrom(512)
                except (queue.Empty, socket.timeout, OSError):
                    break
                parsed = parse_stun(data, txid)
                if parsed:
                    return parsed
    finally:
        if inbox is None:
            sock.settimeout(old)
    return None


def parse_stun(data, txid):
    if len(data) < 20 or data[8:20] != txid or struct.unpack(">H", data[:2])[0] != 0x0101:
        return None
    pos = 20
    while pos + 4 <= len(data):
        kind, length = struct.unpack(">HH", data[pos:pos + 4])
        body = data[pos + 4:pos + 4 + length]
        if kind == 0x0020 and length >= 8 and body[1] == 1:            # XOR-MAPPED-ADDRESS, IPv4
            port = struct.unpack(">H", body[2:4])[0] ^ 0x2112
            ip = bytes(b ^ m for b, m in zip(body[4:8], b"\x21\x12\xa4\x42"))
            return socket.inet_ntoa(ip), port
        if kind == 0x0001 and length >= 8 and body[1] == 1:            # MAPPED-ADDRESS
            return socket.inet_ntoa(body[4:8]), struct.unpack(">H", body[2:4])[0]
        pos += 4 + ((length + 3) & ~3)
    return None


_instance = None


def instance():
    """The one session object of this server process (the chat prepares it, the MSX transaction uses it)."""
    global _instance
    if _instance is None:
        _instance = Netplay(None, None)
    return _instance


def choose_delay(rtts, k=1, service=0):
    """Input delay in frames from measured round trips (seconds), the send interval k (frames) and the
    larger of the two sides' service latency (frames): ceil(rtt90 / 2 / 20 ms) + 2 + (k - 1) + service."""
    s = sorted(rtts)
    rtt = s[int(0.9 * (len(s) - 1))]
    d = int(-(-(rtt * 1000.0 / 2) // FRAME_MS)) + 2 + (k - 1) + service
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
        self.profile_hash = int(env.get("MSXPI_NETPLAY_PROFILE", "0"), 16)
        self.want_k = max(MIN_K, min(MAX_K, int(env.get("MSXPI_NETPLAY_K", "1"))))    # what this side's transport costs:
        self.want_s = max(0, min(255, int(env.get("MSXPI_NETPLAY_S", "0"))))          # K frames apart, S frames to deliver
        self.rng = random.Random(int(env.get("MSXPI_NETPLAY_SEED", "1985")))
        self.lock = threading.RLock()
        self.heap = []                    # (release_time, n, datagram)
        self.n = 0
        self.ready = collections.deque()  # game packets released, in order
        self.sock = None
        self.stun_inbox = queue.Queue()   # STUN replies, handed over by the receive thread
        self.peers = []                   # candidate (ip, port) of the opponent
        self.peer_ips = set()
        self.peer = None                  # the address that answered: locked once known
        self.state = S_IDLE
        self.delay = 0
        self.k = 1                        # the agreed send interval
        self.stats = dict(tx=0, rx=0, dropped=0, badsum=0, delivered=0, malformed=0, deltas_in=0, deltas_out=0)
        self.last_log = 0.0
        self._reset_session()
        if spec:
            lport, host, pport = spec.split(":")
            self.open(int(lport))
            self.set_peers([(host, int(pport))])
            log("netplay: local %s peer %s lag=%.0fms jitter=%.0fms loss=%.1f%% version=%d profile=%08x"
                % (lport, self.peers, self.lag * 1000, self.jitter * 1000, self.loss, self.version, self.profile_hash))

    # ---- session set-up (chat or environment) ---------------------------------------
    def open(self, local_port=0):
        """Bind the UDP socket (once) and start the threads.  Returns the local port."""
        with self.lock:
            if self.sock is None:
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sock.bind(("0.0.0.0", local_port))
                self.sock = sock
                threading.Thread(target=self._rx_loop, args=(sock,), daemon=True).start()
                threading.Thread(target=self._timer_loop, args=(sock,), daemon=True).start()
            return self.sock.getsockname()[1]

    def close(self):
        """End the session and free the port."""
        with self.lock:
            sock, self.sock = self.sock, None
            self.state = S_IDLE
            self.peers, self.peer_ips, self.peer = [], set(), None
            self.heap.clear()
            self.ready.clear()
        if sock:
            sock.close()

    def candidates(self, stun=True, stun_server=None):
        """'ip:port' strings the opponent can try: the LAN address, and the public one (STUN) if it answers.
        STUN uses the game socket itself, so the NAT mapping it learns is the one the game will use."""
        port = self.open()
        found = []
        lan = lan_address()
        if lan:
            found.append("%s:%d" % (lan, port))
        if stun and not os.environ.get("MSXPI_NETPLAY_NOSTUN"):
            public = stun_query(self.sock, stun_server or STUN_SERVER, inbox=self.stun_inbox)
            if public and "%s:%d" % public not in found:
                found.append("%s:%d" % public)
        return found

    def set_peers(self, peers):
        """peers: [(host, port)] - every address the opponent may be reached at.  The first one that
        answers is kept (NAT hole punching: both sides send to all candidates at the same time)."""
        resolved = []
        for host, port in peers:
            try:
                resolved.append((socket.gethostbyname(host), int(port)))
            except OSError:
                pass
        with self.lock:
            self.peers = resolved
            self.peer_ips = {h for h, _ in resolved}
            self.peer = None

    @property
    def configured(self):
        return self.sock is not None and bool(self.peers)

    def describe(self):
        names = {S_IDLE: "idle", S_CONNECT: "connecting", S_SETUP: "connecting", S_READY: "playing",
                 S_INCOMPATIBLE: "different game versions", S_FAILED: "could not connect", S_DEAD: "connection lost",
                 S_LEFT: "the opponent ended it", S_ENDED: "ended"}
        return names.get(self.state, "?")

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
        self.t_ready = None
        self.last_rx = self.t_start
        self.playing = False              # a game packet came from the opponent
        self.delay = 0
        self.k = 1
        self.peer_k, self.peer_s = 1, 0   # what the opponent announced in HELLO
        self.bye_reason = None            # the opponent's result code, from its BYE
        self.local_result = None          # ours, when we sent BYE
        self.bye_left = 0
        self.next_bye = 0.0
        self.ready.clear()
        self.msx_sent = None              # the last game packet the MSX sent (a DELTA's base)
        self.msx_got = None               # the last one given to the MSX

    def restart(self):
        with self.lock:
            self._reset_session()
            self.peer = None
            self.state = S_CONNECT if self.configured else S_FAILED
            self.log("netplay: session restart nonce=%08x%s" % (self.nonce, "" if self.configured else " (not configured)"))

    def bye(self, code):
        """End the game on this side and tell the opponent (BYE, sent BYE_REPEAT times)."""
        with self.lock:
            if self.state in (S_IDLE, S_ENDED):
                return
            self.local_result = code
            self.state = S_ENDED
            self.bye_left, self.next_bye = BYE_REPEAT, 0.0
            self.log("netplay: game ended here (result %d), telling the opponent" % code)

    def _targets(self):
        return [self.peer] if self.peer else self.peers

    def _send(self, data):
        sock = self.sock
        if not sock:
            return
        for target in self._targets():
            try:
                sock.sendto(data, target)
            except OSError:
                pass

    def _send_ctl(self, typ, a=0, b=0):
        self._send(CTL.pack(typ, self.version, self.nonce, a, b))

    def _set_ready(self, now, how):
        self.state = S_READY
        self.t_ready = now
        self.log("netplay: ready, delay %d, K %d%s" % (self.delay, self.k, how))

    # ---- network threads -----------------------------------------------------------
    def _rx_loop(self, sock):
        while True:
            try:
                data, addr = sock.recvfrom(512)
            except OSError:
                if sock.fileno() == -1:
                    return                # closed
                continue                  # e.g. Windows ConnectionResetError after an ICMP
                                          # 'port unreachable' for a peer that is not up yet
            if len(data) >= 20 and data[4:8] == STUN_COOKIE:
                self.stun_inbox.put(data)         # a STUN reply, not the opponent
                continue
            control = len(data) == CTL.size and T_HELLO <= data[0] <= T_BYE
            if not (control or game_packet_ok(data)):
                self.stats["malformed"] += 1
                continue
            with self.lock:
                if self.peer:
                    if addr != self.peer:
                        continue
                elif addr[0] not in self.peer_ips:
                    continue              # not from the opponent
            self.stats["rx"] += 1
            if self.loss and self.rng.random() * 100 < self.loss:
                self.stats["dropped"] += 1
                continue
            t = time.monotonic() + self.lag + (self.rng.random() * self.jitter)
            with self.lock:
                self.n += 1
                heapq.heappush(self.heap, (t, self.n, data, addr))

    def _timer_loop(self, sock):
        while self.sock is sock:
            time.sleep(0.005)
            with self.lock:
                self._pump(time.monotonic())

    def _pump(self, now):
        while self.heap and self.heap[0][0] <= now:
            _, _, data, addr = heapq.heappop(self.heap)
            if self.peer is None and self.state in (S_CONNECT, S_SETUP):
                self.peer = addr          # first answer: keep talking to this address only
                self.log("netplay: opponent at %s:%d" % addr)
            if data[0] == KIND_GAME:
                self._on_game(now, data)
            else:
                self._on_ctl(now, *CTL.unpack(data))
        if self.bye_left and now >= self.next_bye:
            self.bye_left -= 1
            self.next_bye = now + BYE_GAP
            self._send_ctl(T_BYE, self.local_result or 0)
        st = self.state
        if st in (S_CONNECT, S_SETUP):
            if now - self.t_start > CONNECT_TIMEOUT:
                self.state = S_FAILED
                self.log("netplay: connect timed out")
                return
            if now >= self.next_hello and st == S_CONNECT:
                self.next_hello = now + 0.2
                self._send_ctl(T_HELLO, self.profile_hash, self.want_k | (self.want_s << 8))
            if self.leader and st == S_CONNECT and now >= self.next_ping and (
                    self.pings_sent < PINGS or (len(self.rtts) < MIN_SAMPLES and self.pings_sent < MAX_PINGS)):
                self.next_ping = now + 0.1      # keep pinging while too few answers came back
                self.ping_t[self.pings_sent] = now
                self._send_ctl(T_PING, self.pings_sent)
                self.pings_sent += 1
            if self.leader and st == S_CONNECT and len(self.rtts) >= MIN_SAMPLES and (
                    len(self.rtts) >= PINGS or now - self.next_ping > 1.0):
                self.k = max(self.want_k, self.peer_k)
                self.delay = int(os.environ.get('MSXPI_NETPLAY_DELAY', '0')) or choose_delay(
                    self.rtts, self.k, max(self.want_s, self.peer_s))
                self.state = S_SETUP
                self.log("netplay: leader, rtt samples %s, K %d, S %d -> delay %d"
                         % (["%.0f" % (r * 1000) for r in self.rtts], self.k, max(self.want_s, self.peer_s), self.delay))
            if self.state == S_SETUP and now >= self.next_setup:
                self.next_setup = now + 0.2
                self._send_ctl(T_SETUP, self.delay, self.k)
        elif st == S_READY:
            if not self.playing and now - self.t_ready > START_TIMEOUT:
                self.state = S_DEAD
                self.log("netplay: the opponent did not start the game within %.0f s" % START_TIMEOUT)
            elif self.playing and now - self.last_rx > DEAD_AFTER:
                self.state = S_DEAD
                self.log("netplay: no news from the opponent for %.0f s - session dead" % DEAD_AFTER)

    def _on_ctl(self, now, typ, ver, nonce, a, b):
        if self.state == S_IDLE:
            if typ == T_PING:             # still answer pings: the peer may be ahead of us
                self._send_ctl(T_PONG, a)
            return
        incompatible = ver != self.version or (typ == T_HELLO and a != self.profile_hash)
        if incompatible:
            if self.state in (S_CONNECT, S_SETUP):
                self.state = S_INCOMPATIBLE
                self.log("netplay: incompatible opponent (MSXNP %d, profile %08x; ours %d, %08x)"
                         % (ver, a if typ == T_HELLO else 0, self.version, self.profile_hash))
            if self.state == S_INCOMPATIBLE and typ == T_HELLO:
                self._send_ctl(T_HELLO, self.profile_hash, self.want_k | (self.want_s << 8))   # let a peer that started later see it too
            return
        self.last_rx = now
        if typ == T_BYE:
            if self.state in (S_CONNECT, S_SETUP, S_READY):
                self.state = S_LEFT
                self.bye_reason = a & 0xFF
                self.log("netplay: the opponent ended the game (result %d)" % self.bye_reason)
        elif typ == T_HELLO:
            if self.state == S_CONNECT:
                self.peer_k = max(MIN_K, min(MAX_K, b & 0xFF))
                self.peer_s = (b >> 8) & 0xFF
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
            if self.state == S_CONNECT:
                self.delay = a
                self.k = max(MIN_K, min(MAX_K, b))
                self._set_ready(now, " (from the leader)")
            self._send_ctl(T_ACK, a, b)
        elif typ == T_ACK:
            if self.state == S_SETUP and a == self.delay:
                self._set_ready(now, "")

    def _on_game(self, now, data):
        if self.state == S_SETUP:         # the follower started playing: that is the ACK
            self._set_ready(now, " (implicit ack)")
        if self.state == S_READY:
            self.last_rx = now
            self.playing = True
            self.ready.append(data)

    # ---- one MSX transaction -------------------------------------------------------
    def handle(self, opcode, read=None, write=None):
        read = read or self.read
        write = write or self.write
        flags = read()
        length = read() if flags is not None else None
        if length is None:
            return True
        pkt = bytearray()
        for _ in range(length):
            b = read()
            if b is None:
                return True
            pkt.append(b)
        s = read()
        if s is None:
            return True
        if (sum(pkt) & 0xFF) != s or length > MAX_PKT:
            self.stats["badsum"] += 1
            flags &= 0x80                 # corrupted: treat the packet part as lost
        if flags & 4 and flags & 1:       # a DELTA: the packet it stands for
            pkt = undelta(pkt, self.msx_sent)
            if pkt is None:               # not after the base we hold: lost (the MSX resends in full)
                self.stats["malformed"] += 1
                flags &= ~1
            else:
                self.stats["deltas_in"] += 1
        if flags & 0x40:
            self.restart()
        if flags & 0x20:
            self.bye(pkt[0] if pkt else 0)
        with self.lock:
            now = time.monotonic()
            if self.sock:
                self._pump(now)
            if flags & 0x80:
                code = {S_READY: ST_READY, S_INCOMPATIBLE: ST_INCOMPATIBLE, S_FAILED: ST_FAILED,
                        S_DEAD: ST_FAILED, S_LEFT: ST_LEFT, S_ENDED: ST_LEFT}.get(self.state, ST_CONNECTING)
                d = self.delay if code == ST_READY else 0
                if code != getattr(self, '_last_code', None):
                    self._last_code = code
                    self.log('netplay: status -> %d delay %d (state %d)' % (code, d, self.state))
                write(bytes([0xA0 + code, d, self.k if code == ST_READY else 1]))   # state, delay, K
                return True
            if flags & 1 and self.state == S_READY:
                if game_packet_ok(pkt):
                    self._send(bytes(pkt))
                    self.msx_sent = bytes(pkt)
                    self.stats["tx"] += 1
                else:
                    self.stats["malformed"] += 1
            if flags & 2 and self.state in (S_DEAD, S_FAILED):
                write(b"\xff\x00")
                return True
            if flags & 2 and self.state == S_LEFT:
                write(bytes([0xFE, self.bye_reason or 0]))
                return True
            out = self.ready.popleft() if (flags & 2 and self.ready) else b""
            base = self.msx_got if flags & 8 else None
            if out:
                self.msx_got = out
        if out:
            self.stats["delivered"] += 1
            d = delta_of(out, base)
            if d is not None:
                self.stats["deltas_out"] += 1
                out = d
            write(bytes([len(out)]) + out + bytes([sum(out) & 0xFF]))
        else:
            write(b"\x00\x00")
        now = time.monotonic()
        if now - self.last_log > 10:
            self.last_log = now
            self.log("netplay: %s state=%d" % (self.stats, self.state))
        return True
