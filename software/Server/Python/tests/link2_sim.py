"""Lockstep virtual link for LINK2 (documents/LINK2-TEST-PLAN.md, T1).

Two threads stand in for the two ends.  Every byte on the real link is one
full-duplex CPLD transfer that the MSX starts and the Pi answers, so the wire here
is a rendezvous: the Pi offers a MISO byte and waits, the MSX arrives with a MOSI
byte and takes the offer.  The server side is the real msxpi_blocks / msxpi_link2
code, with only the byte primitives replaced; the MSX side is a Python model of
the MSX LINK2 code written from the design document, not from the server.

Fault hooks act on the bytes in flight: Wire.flip(direction, index, mask) XORs
the index-th byte of that direction ('p2m' = Pi -> MSX, 'm2p' = MSX -> Pi).
"""

import os
import sys
import threading
import binascii

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import msxpi_const as C  # noqa: E402
import msxpi_link2  # noqa: E402
import msxpi_blocks  # noqa: E402

# a flipped bit can look like an Ethernet opcode; the TAP side is not under test
msxpi_blocks.eth_handle_opcode = lambda b: False


class Hung(Exception):
    pass


class Wire:
    def __init__(self, timeout=3.0):
        self.cv = threading.Condition()
        self.offer = None
        self.mosi = None
        self.closed = False
        self.timeout = timeout
        self.n = {"p2m": 0, "m2p": 0}
        self.faults = {}  # (direction, index) -> xor mask
        self.log = []  # (direction, byte) as delivered, when tracing
        self.trace = False
        self.hook = None  # hook(direction, index, byte) -> byte, for random faults
        # Slips: MSX transfers that complete without the Pi taking part - a write
        # lost in the CPLD latch, a read that returns a stale byte.  The bit-flip
        # faults above never change how many transfers each side sees; these do.
        self.slips = set()  # MSX transfer numbers that slip
        self.msx_n = 0
        self.stale = 0  # what a slipped read returns: the last byte delivered

    def slip(self, index):
        self.slips.add(index)

    def flip(self, direction, index, mask=0x01):
        self.faults[(direction, index)] = self.faults.get((direction, index), 0) ^ mask

    def _apply(self, d, b):
        i = self.n[d]
        self.n[d] += 1
        b ^= self.faults.get((d, i), 0)
        if self.hook:
            b = self.hook(d, i, b) & 0xFF
        if self.trace:
            self.log.append((d, b))
        return b

    def close(self):
        with self.cv:
            self.closed = True
            self.cv.notify_all()

    # --- Pi side -------------------------------------------------------------
    def pi_xfer(self, miso):
        with self.cv:
            self.offer = miso & 0xFF
            self.cv.notify_all()
            if not self.cv.wait_for(
                lambda: self.mosi is not None or self.closed, self.timeout
            ):
                self.offer = None
                raise Hung("Pi waited for the MSX")
            if self.mosi is None:
                raise Hung("link closed")
            m, self.mosi = self.mosi, None
            return m

    # --- MSX side ------------------------------------------------------------
    def msx_xfer(self, mosi):
        with self.cv:
            n, self.msx_n = self.msx_n, self.msx_n + 1
            if n in self.slips:
                return self.stale  # the Pi never sees this transfer
            if not self.cv.wait_for(
                lambda: self.offer is not None or self.closed, self.timeout
            ):
                raise Hung("MSX waited for the Pi")
            if self.offer is None:
                raise Hung("link closed")
            miso = self._apply("p2m", self.offer)
            self.stale = miso
            self.offer = None
            self.mosi = self._apply("m2p", mosi & 0xFF)
            self.cv.notify_all()
            return miso


class PiIO:
    """The server's view: what msxpi_link2.TransportIO provides."""

    def __init__(self, wire, pi_burst=True):
        self.w = wire
        self.pi_burst = pi_burst

    def byte_in(self):
        return C.RC_SUCCESS, self.w.pi_xfer(0)

    def byte_out(self, b):
        self.w.pi_xfer(b)
        return C.RC_SUCCESS

    def exchange(self, b):
        return C.RC_SUCCESS, self.w.pi_xfer(b)

    def read_payload(self, n):
        return C.RC_SUCCESS, bytes(self.w.pi_xfer(0) for _ in range(n))

    def write_payload(self, data):
        for b in data:
            self.w.pi_xfer(b)
        return C.RC_SUCCESS

    def burst_recv(self, n):
        self.w.pi_xfer(C.LINK_ACK)
        return C.RC_SUCCESS, bytes(self.w.pi_xfer(0) for _ in range(n))

    def burst_send(self, data):
        self.w.pi_xfer(C.LINK_ACK)
        for b in data:
            self.w.pi_xfer(b)
        return C.RC_SUCCESS

    def can_burst(self):
        return self.pi_burst


def crc(data):
    return binascii.crc_hqx(bytes(data), 0xFFFF)  # CRC-16/CCITT-FALSE, as msxpi_link2


class MsxAborted(Exception):
    pass


def in_page1(start, n):
    """The block start .. start+n-1 touches page 1 (4000h-7FFFh), where the MSX never bursts."""
    return n > 0 and start < 0x8000 and start + n - 1 >= 0x4000


class Msx:
    """Model of the MSX LINK2 code (design sections 3.2 and 3.3).

    `at`, where given, is the MSX buffer's address: a transfer whose buffer starts in
    page 1 does not offer bursts, and a block that touches page 1 is not sent as one
    (link2.asm L2_IN_PAGE1).  Without it, `may_burst` alone decides, as before."""

    WRONG_ANSWERS = 16

    def __init__(self, wire, size=8192, has_wait=True):
        self.w = wire
        self.size = size
        self.has_wait = has_wait
        self.stats = {"retries": 0}

    def rd(self):
        return self.w.msx_xfer(0)

    def wr(self, b):
        self.w.msx_xfer(b)

    def open(self, may_burst=True, at=None):
        if at is not None and 0x4000 <= at < 0x8000:
            may_burst = False
        wrong = 0
        while True:
            self.wr(C.HELLO2)
            # answer and flags are always read as a pair, so both ends stay in
            # step when the answer arrives damaged
            ack = self.rd()
            flags = self.rd()
            if ack == C.HELLO2_ACK:
                break
            wrong += 1
            if wrong >= self.WRONG_ANSWERS:
                raise MsxAborted("server does not speak LINK2")
        self.pi_burst = bool(flags & C.LINK2_FLAG_BURST)
        word = self.size | (0x8000 if (self.has_wait and may_burst) else 0)
        frame = bytes((C.SIZE_MARK, word & 0xFF, word >> 8))
        c = crc(frame)
        for _ in range(C.LINK2_SENDER_CAP):
            for b in frame + bytes((c & 0xFF, c >> 8)):
                self.wr(b)
            a = self.rd()
            if a == C.LINK_ABORT:
                raise MsxAborted("server aborted (open)")
            if a != C.LINK_NAK:
                break
        else:
            raise MsxAborted("open: sender cap reached")
        self.burst_ok = self.pi_burst and self.has_wait and may_burst

    def send(self, data, may_burst=True, at=None):
        """LINK_SEND: one transfer of one or more blocks."""
        self.open(may_burst, at)
        data = bytes(data)
        # the server learns our size from the word; blocks are limited by it
        seq = 0
        off = 0
        while True:
            end = min(off + self.size, len(data))
            last = end >= len(data)
            self._send_block(data[off:end], C.RC_SUCCESS if last else C.RC_READY, seq,
                             None if at is None else at + off)
            seq = (seq + 1) & 0xFF
            if last:
                return
            off = end

    def _send_block(self, payload, typ, seq, at=None):
        burst = self.burst_ok and payload and not len(payload) % 256
        if at is not None and in_page1(at, len(payload)):
            burst = False
        hdr = bytes([typ, len(payload) & 0xFF, (len(payload) >> 8) & 0x7F | (0x80 if burst else 0), seq])
        hc = crc(hdr)
        pc = crc(payload)
        for attempt in range(C.LINK2_SENDER_CAP):
            if attempt:
                self.stats["retries"] += 1
            for b in hdr + bytes([hc & 0xFF, hc >> 8]):
                self.wr(b)
            a = self.rd()
            if a == C.LINK_ABORT:
                raise MsxAborted("server aborted (header)")
            if a == C.LINK_NAK:
                continue
            # (burst: this ACK was the GO byte)
            for b in payload:
                self.wr(b)
            self.wr(pc & 0xFF)
            self.wr(pc >> 8)
            self.wr(seq ^ 0xFF)  # end mark
            a = [self.rd() for _ in range(2 if typ != C.RC_READY else 1)]
            if C.LINK_ACK in a:
                return
            if C.LINK_ABORT in a:
                raise MsxAborted("server aborted (payload)")
        raise MsxAborted("sender cap reached")

    def recv(self, maxbuf=65536, may_burst=True, at=None):
        """LINK_RECV: a whole transfer from the Pi.  (Whether the MSX reads a burst with
        INIR or polled does not show on the wire: only the open frame depends on `at`.)"""
        self.open(may_burst, at)
        out = bytearray()
        last_seq = None
        next_seq = 0
        naks = 0
        while True:
            hdr = bytes(self.rd() for _ in range(4))
            hcrc = self.rd() | (self.rd() << 8)
            if crc(hdr) != hcrc:
                naks = self._nak(naks)
                continue
            typ, lo, hi, seq = hdr
            self.cur_typ = typ
            burst = bool(hi & 0x80)
            length = lo | ((hi & 0x7F) << 8)
            dup = seq == last_seq
            valid_type = C.RC_SUCCESS <= typ <= C.RC_PROTOERR
            if not valid_type or not (dup or seq == next_seq) or length > self.size:
                self.wr(C.LINK_ABORT)  # header slot: single
                self._flood()
                raise MsxAborted("bad header")
            self.wr(C.LINK_ACK)
            if burst:
                self.rd()  # polled GO: its value is not checked, it only syncs
            payload = bytes(self.rd() for _ in range(length))
            pcrc = self.rd() | (self.rd() << 8)
            end = self.rd()
            if crc(payload) != pcrc or end != seq ^ 0xFF:
                naks = self._nak(naks, True)
                continue
            self.wr(C.LINK_ACK)
            if typ != C.RC_READY:
                self.wr(C.LINK_ACK)  # the final answer goes out twice
            if dup:
                continue
            last_seq = seq
            next_seq = (seq + 1) & 0xFF
            out += payload
            if typ != C.RC_READY:
                return bytes(out)

    FLOOD_MARGIN = 16

    def _flood(self):
        """Keep answering ABORT for one block and its framing, so a Pi that
        slipped out of step meets it at its next answer slot (design 3.7)."""
        for _ in range(self.size + self.FLOOD_MARGIN):
            self.wr(C.LINK_ABORT)

    def _nak(self, naks, payload=False):
        naks += 1
        self.stats["retries"] += 1
        twice = payload and self.cur_typ != C.RC_READY
        code = C.LINK_ABORT if naks >= C.LINK2_RETRIES else C.LINK_NAK
        self.wr(code)
        if twice:
            self.wr(code)
        if code == C.LINK_ABORT:
            self._flood()
            raise MsxAborted("receiver limit")
        return naks


class Server:
    """Runs server-side scripted steps on a thread, over a Wire."""

    def __init__(self, wire, steps, pi_burst=True):
        self.w = wire
        self.steps = steps
        self.results = []
        self.error = None
        msxpi_link2.io = PiIO(wire, pi_burst)
        self.t = threading.Thread(target=self.run, daemon=True)

    def run(self):
        def spi(b=None):
            if b is None:
                return C.RC_SUCCESS, self.w.pi_xfer(0)
            self.w.pi_xfer(b)
            return C.RC_SUCCESS, 0

        saved = {
            n: getattr(msxpi_blocks, n)
            for n in ("link_recv_byte", "link_send_byte", "SPI_ReadPayload",
                      "SPI_WritePayload", "SPI_BurstIn", "SPI_BurstOut")
        }
        w = self.w
        msxpi_blocks.link_recv_byte = msxpi_blocks.link_send_byte = spi
        msxpi_blocks.SPI_ReadPayload = lambda n: (
            C.RC_SUCCESS, bytearray(w.pi_xfer(0) for _ in range(n)))
        msxpi_blocks.SPI_BurstIn = msxpi_blocks.SPI_ReadPayload
        msxpi_blocks.SPI_WritePayload = lambda d: [w.pi_xfer(b) for b in d] and C.RC_SUCCESS
        msxpi_blocks.SPI_BurstOut = msxpi_blocks.SPI_WritePayload
        try:
            for step in self.steps:
                self.results.append(step())
        except Hung as e:
            self.error = e
        except Exception as e:  # noqa: BLE001
            self.error = e
        finally:
            for n, f in saved.items():
                setattr(msxpi_blocks, n, f)

    def start(self):
        self.t.start()
        return self

    def join(self, timeout=10):
        self.t.join(timeout)
        return not self.t.is_alive()


class LegacyMsx:
    """Model of the shipped MSX SENDDATA (legacy protocol), for mixed traffic."""

    def __init__(self, wire, size=512):
        self.w = wire
        self.size = size

    def rd(self):
        return self.w.msx_xfer(0)

    def wr(self, b):
        self.w.msx_xfer(b)

    def send(self, data):
        self.wr(C.READY)
        assert self.rd() == C.READY_ACK
        self.wr(self.size & 0xFF)
        self.wr(self.size >> 8)
        off, idx = 0, 0
        data = bytes(data)
        while True:
            end = min(off + self.size, len(data))
            blk = data[off:end]
            last = end >= len(data)
            s = sum(blk)
            chk = ((s & 0xFF) + ((s >> 8) & 0xFF)) & 0xFF
            for b in (C.RC_SUCCESS if last else C.RC_READY, len(blk) & 0xFF, len(blk) >> 8, idx):
                self.wr(b)
            for b in blk:
                self.wr(b)
            self.wr(chk)
            assert self.rd() == chk
            assert self.rd() == C.READY  # status handshake: Pi sends READY, status
            assert self.rd() == C.RC_SUCCESS
            self.wr(C.READY_ACK)
            if last:
                return
            off, idx = end, (idx + 1) & 0xFF


# LINK2_MSX=z80 runs every test against the assembled Z80 code (z80_msx.py) instead of the
# Python model above; the model stays reachable as ModelMsx.
ModelMsx = Msx
if os.environ.get("LINK2_MSX") == "z80":
    from z80_msx import Z80Msx as Msx  # noqa: E402,F811
