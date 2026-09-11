# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

# =============================================================================
# msxpi_eth.py - Ethernet UNAPI shuttle for the MSXPi server
# =============================================================================
# Moves raw Ethernet frames between a Linux TAP device and the MSX, so that a
# driver on the MSX side can implement the 12-routine Ethernet UNAPI and let
# InterNestor Lite run the TCP/IP stack on the Z80.
#
# Architecturally this is PiSCSI's DaynaPORT emulation: the Pi is a dumb wire,
# not a TCP/IP stack.  The read header, the "more frames pending" flag, the
# non-blocking poll and the software CRC32 are all lifted from
# cpp/devices/scsi_daynaport.cpp and cpp/devices/ctapdriver.cpp.
#
# Design notes that are easy to get wrong, all from UNAPI/PHASE1_DESIGN.md:
#
#  * InterNestor Lite calls ETH_IN_STATUS from the 50/60 Hz timer interrupt.
#    Every operation here must therefore answer IMMEDIATELY from a buffer.
#    Nothing in this module may block on the network.
#
#  * ETH_GET_FRAME returns the status of the NEXT frame in its own header, so
#    INL's following ETH_IN_STATUS needs no round trip at all.  On a link this
#    slow that is the single biggest win available.
#
#  * The Ethernet UNAPI spec says that when the receive buffer is full, NEW
#    frames are discarded and the OLDEST are preserved.  That is the opposite
#    of the usual ring-buffer behaviour, so RX_QUEUE_MAX is enforced by
#    checking before append, not by using a self-evicting deque.
#
#  * TAP hands up frames with no FCS, so the CRC is generated here.
# =============================================================================

import os
import struct
import threading
import collections

# --- Wire protocol ----------------------------------------------------------
#
# The MSX signals a fast op by sending an opcode byte where recvdata2() is
# waiting for READY ($AA).  recvdata2() ignores every non-READY byte, so the
# opcode range only has to avoid the values that loop already reacts to.
# $A0-$AE (READY/ACK/BUSY...) and $E0-$EF (RC_*) are taken; $C0-$CF is free.

OP_PROBE       = 0xC0   # protocol handshake / presence check
OP_GET_HWADD   = 0xC1
OP_GET_NETSTAT = 0xC2
OP_NET_ONOFF   = 0xC3
OP_FILTERS     = 0xC4
OP_IN_STATUS   = 0xC5   # the hot path - INL calls this 50/60 times a second
OP_GET_FRAME   = 0xC6   # bulk
OP_SEND_FRAME  = 0xC7   # bulk
OP_RESET       = 0xC8

# frozenset, not a tuple: this is tested against EVERY byte the server reads
# while waiting for READY, so a linear scan is paid on all ordinary traffic too,
# not just on opcodes.
OPCODES = frozenset((OP_PROBE, OP_GET_HWADD, OP_GET_NETSTAT, OP_NET_ONOFF,
                     OP_FILTERS, OP_IN_STATUS, OP_GET_FRAME, OP_SEND_FRAME,
                     OP_RESET))

# Fast ops answer with [RC] followed by a fixed number of data bytes.  The
# length is a property of the opcode, known to both sides in advance, so there
# is never any framing ambiguity - even after an aborted transfer, both ends
# resynchronise on the next opcode.
FAST_REPLY_LEN = {
    OP_PROBE:       4,   # 'E','T','H', protocol version
    OP_GET_HWADD:   6,   # MAC address
    OP_GET_NETSTAT: 1,   # 0 = closed, 1 = open
    OP_NET_ONOFF:   1,   # resulting state
    OP_FILTERS:     1,   # resulting filter bits
    OP_RESET:       1,   # 0 = ok
}

PROTO_VERSION = 1

ETH_RC_OK       = 0x00
ETH_RC_ERR      = 0x01
ETH_RC_BADLEN   = 0x02
ETH_RC_CHKSUM   = 0x03

# Flag bits in the ETH_GET_FRAME reply header.
FLAG_MORE_PENDING = 0x01

# How many received frames to hold.  Each is up to MAX_FRAME bytes; 64 frames
# is generous for a link this slow and bounds memory at ~100 KB.
RX_QUEUE_MAX = 64

# Ethernet UNAPI allows 16..1514 for sends.  Incoming frames larger than this
# are dropped rather than truncated - a truncated frame would fail its checksum
# on the MSX side and waste a whole transfer.
MAX_FRAME = 1514
MIN_FRAME = 16

# PiSCSI pads short frames to 128 rather than the 64 the spec asks for: several
# real drivers break below that (PiSCSI issues #619 and #1098).  We generate
# the CRC ourselves so padding stays consistent with the checksum.
PAD_TO = 128

# Receive-side padding, and a different job from PAD_TO above.
#
# Real Ethernet hardware never delivers a frame shorter than the 64-byte
# minimum, because the SENDING NIC pads it. A TAP device has no NIC and does no
# padding, so without this the MSX is handed 42-byte ARP frames that no real
# card could ever produce - and Ethernet UNAPI ETH_FILTERS bit 1 ("accept small
# frames, smaller than 64 bytes") explicitly entitles the client to drop them.
#
# InterNestor Lite does exactly that. On hardware it fetched every ARP request
# for its own address - ETHTEST confirmed the queue was being drained - and
# discarded all of them, so ETH_OUT_STATUS stayed at 0, "nothing sent since
# reset", and the Pi's ARP went unanswered indefinitely. Receive worked
# perfectly at every layer below; the frames were simply too short to be legal.
RX_PAD_TO = 64


# =============================================================================
# CRC32 - same polynomial and bit order as CTapDriver::Crc32
# =============================================================================

def eth_crc32(data):
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            mask = -(crc & 1)
            crc = (crc >> 1) ^ (0xEDB88320 & mask)
    return (~crc) & 0xFFFFFFFF


# =============================================================================
# Link backends
# =============================================================================

class BaseLink(object):
    """Common queue handling.  Subclasses only supply transmit and teardown."""

    def __init__(self, mac=b"\x02\x4d\x53\x58\x50\x69"):   # 02:4d:53:58:50:69
        # Locally-administered MAC (first octet bit 1 set), spelling "MSXPi".
        self.mac = bytes(mac)
        self.rx = collections.deque()
        self.lock = threading.Lock()
        self.enabled = True
        # ETH_FILTERS bitmask, in the specification's own bit order:
        #   bit 4 promiscuous, bit 2 accept broadcast, bit 1 accept small frames.
        # ETH_RESET defines the default as "accept broadcast and small frames,
        # promiscuous off", i.e. 0x06.
        self.filters = 0x06
        self.dropped = 0
        self.running = True

    # --- receive side -------------------------------------------------------

    def _push(self, frame):
        """Called by the reader thread.  Never blocks the MSX side."""
        if not self.enabled:
            return
        if len(frame) > MAX_FRAME:
            self.dropped += 1
            return
        # Stand in for the sending NIC that a TAP device does not have.  Done
        # here rather than at pop() so that the length ETH_IN_STATUS reports
        # and the length ETH_GET_FRAME delivers are necessarily the same
        # number - the client reads them as a pair and a mismatch would be a
        # much nastier bug than the one this fixes.
        if len(frame) < RX_PAD_TO:
            frame = bytes(frame) + b"\x00" * (RX_PAD_TO - len(frame))
        with self.lock:
            # Spec: when the buffer is full, discard NEW frames and keep the
            # oldest.  Hence the explicit length check.
            if len(self.rx) >= RX_QUEUE_MAX:
                self.dropped += 1
                return
            self.rx.append(bytes(frame))

    def peek(self):
        """(length, ethertype_word) of the oldest frame, or (0, 0)."""
        with self.lock:
            if not self.rx:
                return (0, 0)
            f = self.rx[0]
            et = (f[12] << 8) | f[13] if len(f) >= 14 else 0
            return (len(f), et)

    def pop(self):
        """Oldest frame and whether another is queued behind it."""
        with self.lock:
            if not self.rx:
                return (None, False)
            f = self.rx.popleft()
            return (f, len(self.rx) > 0)

    def pending(self):
        with self.lock:
            return len(self.rx)

    # --- transmit side ------------------------------------------------------

    def transmit(self, frame):
        raise NotImplementedError

    def link_up(self):
        return False

    def close(self):
        self.running = False


class MockLink(BaseLink):
    """Frames in memory.  Runs anywhere, including Windows.

    This is what makes the openMSX harness able to exercise the whole protocol
    without a Pi, a TAP device or a network: a test injects frames with
    inject(), drives the MSX, and reads back what the MSX transmitted from
    self.sent.
    """

    def __init__(self, *a, **kw):
        BaseLink.__init__(self, *a, **kw)
        self.sent = []
        self.enabled = True

    def inject(self, frame):
        # Bypass self.enabled so a test can queue frames before the driver has
        # brought the interface up.
        was, self.enabled = self.enabled, True
        try:
            self._push(frame)
        finally:
            self.enabled = was

    def transmit(self, frame):
        self.sent.append(bytes(frame))
        return True

    def link_up(self):
        return True


class TapLink(BaseLink):
    """A real Linux TAP device, read by a background thread.

    The thread exists so that the MSX-facing operations never touch the
    network: they only ever look at the deque.  See the header note about
    InterNestor Lite calling in from the timer interrupt.
    """

    TUNSETIFF   = 0x400454CA
    IFF_TAP     = 0x0002
    IFF_NO_PI   = 0x1000

    def __init__(self, ifname="msxpi0", *a, **kw):
        BaseLink.__init__(self, *a, **kw)
        import fcntl
        self.ifname = ifname
        self.fd = os.open("/dev/net/tun", os.O_RDWR)
        ifr = struct.pack("16sH", ifname.encode(), self.IFF_TAP | self.IFF_NO_PI)
        fcntl.ioctl(self.fd, self.TUNSETIFF, ifr)
        self.enabled = True
        self.thread = threading.Thread(target=self._reader, name="msxpi-tap")
        self.thread.daemon = True
        self.thread.start()

    def _reader(self):
        import select
        while self.running:
            try:
                # Short timeout rather than a blocking read so that close()
                # actually ends the thread.
                r, _, _ = select.select([self.fd], [], [], 0.25)
                if not r:
                    continue
                self._push(os.read(self.fd, MAX_FRAME + 4))
            except OSError:
                if self.running:
                    continue
                break

    def transmit(self, frame):
        try:
            os.write(self.fd, frame)
            return True
        except OSError:
            return False

    def link_up(self):
        return True

    def close(self):
        BaseLink.close(self)
        try:
            os.close(self.fd)
        except OSError:
            pass


# =============================================================================
# Shuttle - opcode dispatch
# =============================================================================

class EthShuttle(object):
    """Serves Ethernet UNAPI opcodes over the MSXPi byte transport.

    The transport is injected rather than imported so that this module has no
    dependency on msxpi-server.py (which would be circular) and can be unit
    tested with a fake:

        read_byte()        -> (rc, value)   receive one byte; value None on error
        write_byte(value)  -> 0 on success  send one byte to the MSX
        write_burst(bytes) -> 0 on success  optional; see the note below

    Note the convention: the write callables return **0 for success**, not the
    server's RC_SUCCESS.  RC_SUCCESS is 0xE0, which is truthy, so passing it
    through unmapped would make every write look like a failure.  Keeping this
    module free of the server's RC_* namespace is what lets it be unit tested
    standalone; the mapping belongs in the caller.

    write_burst is what lets the MSX use INIR.  Hardware /WAIT is gated on
    SPI_RDY, and the per-byte SPI_ByteTransfer() raises and drops RPI_READY
    around every single byte - during that gap an INIR read would NOT stall and
    would silently return a stale byte.  A burst-capable transport must hold
    RPI_READY high for the whole run.  Without one, everything here still works
    via write_byte, just at legacy speed.
    """

    def __init__(self, link, read_byte, write_byte, write_burst=None,
                 log=None):
        self.link = link
        self._read = read_byte
        self._write = write_byte
        self._burst = write_burst
        self._log = log or (lambda *a: None)

        # Dict dispatch, built once, instead of an if/elif chain walked on every
        # opcode. Bound methods are stored directly so a call costs one dict
        # lookup rather than up to nine comparisons plus an attribute lookup.
        #
        # Worth doing because the per-transaction fixed cost - not the per-byte
        # cost - dominates short transactions, and ETH_IN_STATUS is a 6-byte
        # transaction InterNestor Lite issues sixty times a second.
        self._dispatch = {
            OP_PROBE:       self._op_probe,
            OP_GET_HWADD:   self._op_get_hwadd,
            OP_GET_NETSTAT: self._op_get_netstat,
            OP_NET_ONOFF:   self._op_net_onoff,
            OP_FILTERS:     self._op_filters,
            OP_RESET:       self._op_reset,
            OP_IN_STATUS:   self._op_in_status,
            OP_GET_FRAME:   self._op_get_frame,
            OP_SEND_FRAME:  self._op_send_frame,
        }

        # Replies that never change are built once here rather than being
        # reassembled per call.
        self._probe_reply = bytes([ETH_RC_OK]) + b"ETH" + bytes([PROTO_VERSION])
        self._netstat_up   = bytes([ETH_RC_OK, 1])
        self._netstat_down = bytes([ETH_RC_OK, 0])

    def _op_probe(self):
        self._write_many(self._probe_reply)

    def _op_get_hwadd(self):
        self._fast(ETH_RC_OK, self.link.mac)

    def _op_get_netstat(self):
        self._write_many(self._netstat_up if self.link.link_up()
                         else self._netstat_down)

    # --- helpers ------------------------------------------------------------

    def _write_many(self, data):
        if self._burst is not None:
            return self._burst(bytes(data))
        for b in bytearray(data):
            rc = self._write(b)
            if rc:
                return rc
        return 0

    def _read_n(self, n):
        out = bytearray()
        for _ in range(n):
            rc, v = self._read()
            if v is None:
                return None
            out.append(v)
        return bytes(out)

    # --- entry point --------------------------------------------------------

    def handle(self, opcode):
        """Dispatch one opcode.  Returns True if it was ours.

        Called from the byte the server was about to discard, so an opcode we
        do not recognise must be reported as not-ours and left alone.
        """
        handler = self._dispatch.get(opcode)
        if handler is None:
            return False
        handler()
        return True

    def _fast(self, rc, payload):
        self._write_many(bytes([rc]) + payload)

    # --- individual operations ---------------------------------------------

    def _op_net_onoff(self):
        """ETH_NET_ONOFF.  Argument and reply use the UNAPI encoding directly:
        0 = query, 1 = enable, 2 = disable; reply 1 = enabled, 2 = disabled."""
        rc, arg = self._read()
        if arg is None:
            return
        if arg == 1:
            self.link.enabled = True
        elif arg == 2:
            self.link.enabled = False
        self._fast(ETH_RC_OK, bytes([1 if self.link.enabled else 2]))

    def _op_filters(self):
        """ETH_FILTERS.  Bit 7 of the argument means "report only, change
        nothing" - that is the specification's own encoding, so the byte is
        passed through from the MSX untranslated."""
        rc, arg = self._read()
        if arg is None:
            return
        if not (arg & 0x80):
            self.link.filters = arg & 0x7F
        self._fast(ETH_RC_OK, bytes([self.link.filters]))

    def _op_reset(self):
        """ETH_RESET: back to the state defined in specification section 3.2 -
        networking enabled, queued frames discarded, default filters."""
        with self.link.lock:
            self.link.rx.clear()
        self.link.dropped = 0
        self.link.enabled = True
        self.link.filters = 0x06
        self._fast(ETH_RC_OK, bytes([0]))

    def _op_in_status(self):
        """ETH_IN_STATUS.  Reply: [RC][LEN_LO][LEN_HI][ET_HI][ET_LO].

        RC is 1 when a frame is waiting, 0 when not - matching what the UNAPI
        routine has to return in A.  LEN and the ether-type go straight into
        BC and HL.
        """
        length, et = self.link.peek()
        self._write_many(bytes([1 if length else 0,
                                length & 0xFF, (length >> 8) & 0xFF,
                                (et >> 8) & 0xFF, et & 0xFF]))

    def _op_get_frame(self):
        """ETH_GET_FRAME.

        MSX -> [C6][MAXLEN_LO][MAXLEN_HI]
        Pi  -> [LEN_LO][LEN_HI][FLAGS]                      when LEN == 0
               [LEN_LO][LEN_HI][FLAGS][frame...][CHKSUM]    otherwise

        FLAGS bit 0 says another frame is already queued, so INL's next
        ETH_IN_STATUS is answerable without a round trip (the PiSCSI trick).
        """
        hdr = self._read_n(2)
        if hdr is None:
            return
        maxlen = hdr[0] | (hdr[1] << 8)

        frame, more = self.link.pop()
        if frame is None:
            self._write_many(b"\x00\x00\x00")
            return

        if maxlen and len(frame) > maxlen:
            # The MSX cannot hold it.  Drop it rather than truncate: a partial
            # frame is useless to the stack and costs a whole slow transfer.
            self._log("eth: frame of %d exceeds MSX buffer %d, dropped"
                      % (len(frame), maxlen))
            more = self.link.pending() > 0
            self._write_many(bytes([0, 0, FLAG_MORE_PENDING if more else 0]))
            return

        flags = FLAG_MORE_PENDING if more else 0
        body = bytes(frame)
        chk = sum(bytearray(body)) & 0xFF
        self._write_many(bytes([len(body) & 0xFF, (len(body) >> 8) & 0xFF,
                                flags]) + body + bytes([chk]))

    def _op_send_frame(self):
        """ETH_SEND_FRAME.

        MSX -> [C7][LEN_LO][LEN_HI][frame...][CHKSUM]
        Pi  -> [RC]
        """
        hdr = self._read_n(2)
        if hdr is None:
            return
        length = hdr[0] | (hdr[1] << 8)

        if length < MIN_FRAME or length > MAX_FRAME:
            self._write(ETH_RC_BADLEN)
            return

        body = self._read_n(length)
        if body is None:
            return
        rc, chk = self._read()
        if chk is None:
            return

        if (sum(bytearray(body)) & 0xFF) != chk:
            self._log("eth: send checksum mismatch")
            self._write(ETH_RC_CHKSUM)
            return

        # Pad, then append the FCS the TAP device does not supply.
        out = body
        if len(out) < PAD_TO:
            out = out + b"\x00" * (PAD_TO - len(out))
        out = out + struct.pack("<I", eth_crc32(out))

        ok = self.link.transmit(out)
        self._write(ETH_RC_OK if ok else ETH_RC_ERR)


# =============================================================================
# Factory
# =============================================================================

def make_link(prefer_tap=True, ifname="msxpi0", log=None):
    """A TapLink where possible, a MockLink everywhere else.

    Falling back rather than raising is deliberate: the openMSX harness runs on
    Windows, where there is no /dev/net/tun, and every phase before real
    networking is exercised entirely through MockLink.
    """
    log = log or (lambda *a: None)
    if prefer_tap and os.path.exists("/dev/net/tun"):
        try:
            link = TapLink(ifname=ifname)
            log("eth: TAP device %s up" % ifname)
            return link
        except Exception as e:
            log("eth: TAP unavailable (%s) - falling back to MockLink" % e)
    else:
        log("eth: no /dev/net/tun - using MockLink")
    return MockLink()
