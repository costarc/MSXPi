# MSXPi Interface
# Version 1.6.1
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

"""LINK2, the framed, CRC-16 protected block protocol (documents/LINK2-DESIGN.md).

Server side only.  The MSX opens a transfer with HELLO2, and from then on every
block is

    S -> type, len lo, len hi, seq, hcrc lo, hcrc hi
    R -> ACK | NAK | ABORT          (for a burst this ACK is the GO byte when R is the Pi)
    [Pi -> ACK]                     (GO byte, Pi -> MSX bursts only)
    S -> payload, crc lo, crc hi
    R -> ACK | NAK | ABORT

The receiver alone decides when to give up (LINK2_RETRIES consecutive NAKs); the
sender only has a safety cap.  Names follow LINK2-DESIGN.md 5.3: what the MSX
sends the Pi receives (link2_recv*), and the other way round (link2_send*).

The wire is reached through a small io object so the same code runs on the real
transport and on the simulated link of tests/link2_sim.py.
"""

from __future__ import annotations

import binascii
from typing import Optional, Tuple

from msxpi_const import (
    HELLO2,
    HELLO2_ACK,
    LINK2_FLAG_BURST,
    LINK2_RETRIES,
    LINK2_SENDER_CAP,
    LINK_ABORT,
    LINK_ACK,
    LINK_NAK,
    SIZE_MARK,
    RC_BUFOVFLW,
    RC_CONNERR,
    RC_FAILED,
    RC_PROTOERR,
    RC_READY,
    RC_SUCCESS,
    READY,
)

BURST_BIT = 0x8000  # in the block length: this payload bursts
WAIT_BIT = 0x8000  # in the MSX's size word: this transfer may burst
MAX_BLOCK = 0x7FFF


# Init 0xFFFF, not 0 (CRC-16/XMODEM): with 0 an all-zero frame has CRC 0, so the
# idle link - a hunting Pi offers 0x00 on every transfer - read as a valid empty
# block by an MSX that had slipped out of step (the slip sweep, design 3.7).
CRC_INIT = 0xFFFF


def link_crc(data: bytes | bytearray, crc: int = CRC_INIT) -> int:
    """CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflection)."""
    return binascii.crc_hqx(bytes(data), crc)


def _valid_type(typ: int) -> bool:
    """A header type is RC_READY (more blocks follow) or another RC code (the
    last block); anything else is not a header at all."""
    return RC_SUCCESS <= typ <= RC_PROTOERR


class TransportIO:
    """The real wire: the primitives of msxpi_transport."""

    def __init__(self):
        import msxpi_transport as t

        self.t = t

    def byte_in(self) -> Tuple[int, Optional[int]]:
        return self.t.link_recv_byte()

    def byte_out(self, b: int) -> int:
        return self.t.link_send_byte(b & 0xFF)[0]

    def exchange(self, b: int) -> Tuple[int, Optional[int]]:
        """Send b and return what the MSX sent in the same transfer."""
        return self.t.link_send_byte(b & 0xFF)

    def read_payload(self, n: int):
        return self.t.SPI_ReadPayload(n)

    def write_payload(self, data) -> int:
        return self.t.SPI_WritePayload(data)

    def burst_recv(self, n: int):
        """GO, then n bytes in one READY-held run."""
        return self.t.spi_burst_recv(n, LINK_ACK)

    def burst_send(self, data) -> int:
        """GO, then the payload, in one READY-held run."""
        return self.t.spi_burst_send(data, LINK_ACK)

    def can_burst(self) -> bool:
        return self.t.burst_capable()


io: object = None  # set on first use, or by a test


def _io():
    global io
    if io is None:
        io = TransportIO()
    return io


class Transfer:
    """State of one open transfer; nothing outlives it."""

    def __init__(self, msx_size: int, pi_burst: bool):
        self.msx_wait = bool(msx_size & WAIT_BIT)
        self.msx_size = msx_size & ~WAIT_BIT
        self.pi_burst = pi_burst
        self.burst_ok = self.msx_wait and pi_burst
        self.next_seq = 0  # seq the receiver expects
        self.last_seq: Optional[int] = None  # last seq accepted (duplicate check)
        self.send_seq = 0  # seq the sender uses next


def _abort_flood(o, count: int) -> None:
    """ABORT, and keep answering ABORT.

    A sender that slipped out of step (a transfer one side saw and the other did
    not) reads its answer slots at the wrong place, and a single ABORT lands in a
    slot it never reads.  Repeating it until the sender reaches an answer slot -
    at most one block and its framing away - always hits one.  Stops as soon as
    the MSX starts a new transfer: its HELLO2 or READY arrives in the same
    transfers, so the next command is not held up.
    """
    for _ in range(count):
        rc, b = o.exchange(LINK_ABORT)
        if rc != RC_SUCCESS or b in (HELLO2, READY):
            return


FLOOD_MARGIN = 16  # framing bytes around a payload, with room to spare


def _hdr(typ: int, length: int, seq: int) -> bytes:
    h = bytes((typ & 0xFF, length & 0xFF, (length >> 8) & 0xFF, seq & 0xFF))
    c = link_crc(h)
    return h + bytes((c & 0xFF, c >> 8))


def link2_accept() -> Tuple[int, Optional[Transfer]]:
    """The HELLO2 byte has just been read: answer it and take the MSX's size frame.

    HELLO2_ACK, flags, then the MSX sends  SIZE_MARK, lo, hi, crc-lo, crc-hi  and
    gets ACK or NAK.  A HELLO2 where the mark should be means the MSX missed our
    answer and is asking again: answer again, so a corrupted HELLO2_ACK costs one
    retry and nothing else.  As everywhere, an ACK that arrives garbled counts as
    ACK on the MSX side (see link2_send_block); here the Pi only ever sends it.
    """
    o = _io()
    flags = LINK2_FLAG_BURST if o.can_burst() else 0

    def hello() -> bool:
        return (
            o.byte_out(HELLO2_ACK) == RC_SUCCESS and o.byte_out(flags) == RC_SUCCESS
        )

    if not hello():
        return RC_CONNERR, None
    naks = 0
    while True:
        rc, b = o.byte_in()
        if rc != RC_SUCCESS:
            return RC_CONNERR, None
        if b == HELLO2:
            if not hello():
                return RC_CONNERR, None
            continue
        # Anything else starts a size frame (five bytes; the MSX sends it whole and
        # then waits for the answer), so a damaged mark is NAKed like any other
        # damage instead of being skipped.
        rc, f = o.read_payload(4)
        if rc != RC_SUCCESS:
            return RC_CONNERR, None
        if b == SIZE_MARK and link_crc(bytes((b, f[0], f[1]))) == f[2] | (f[3] << 8):
            if o.byte_out(LINK_ACK) != RC_SUCCESS:
                return RC_CONNERR, None
            return RC_SUCCESS, Transfer(f[0] | (f[1] << 8), bool(flags))
        naks += 1
        if naks >= LINK2_RETRIES:
            _abort_flood(o, 5 + FLOOD_MARGIN)
            return RC_PROTOERR, None
        o.byte_out(LINK_NAK)


def link2_recv_block(
    tr: Transfer, max_len: int
) -> Tuple[int, Optional[int], Optional[bytes]]:
    """Receive one block from the MSX.

    Returns (RC_SUCCESS, header type, payload) for an accepted block (header type
    RC_READY: more follow), or (error rc, None, None) after the receiver has
    aborted or the wire failed.  A duplicate (its ACK was lost) is read,
    discarded and ACKed again, then the next block is awaited.
    """
    o = _io()
    naks = 0
    typ = RC_READY  # what the last valid header said; the final block's answer is doubled

    def answer(code: int) -> bool:
        """The answer after a payload.  For the final block it goes out twice and
        the sender takes either: the final answer is the one a damaged byte can
        not be recovered from, because the receiver leaves as soon as it is sent."""
        ok = o.byte_out(code) == RC_SUCCESS
        if typ != RC_READY:
            ok = o.byte_out(code) == RC_SUCCESS and ok
        return ok

    def nak(payload_phase: bool = True) -> bool:
        """Answer NAK, or ABORT when the limit is reached; True = keep going."""
        nonlocal naks
        naks += 1
        send = answer if payload_phase else o.byte_out
        if naks >= LINK2_RETRIES:
            send(LINK_ABORT)
            _abort_flood(o, max_len + FLOOD_MARGIN)
            return False
        return bool(send(LINK_NAK))

    while True:
        rc, hdr = o.read_payload(6)
        if rc != RC_SUCCESS:
            return RC_CONNERR, None, None
        if link_crc(hdr[:4]) != hdr[4] | (hdr[5] << 8):
            if not nak(False):
                return RC_PROTOERR, None, None
            continue
        typ = hdr[0]
        wire_len = hdr[1] | (hdr[2] << 8)
        seq = hdr[3]
        burst = bool(wire_len & BURST_BIT)
        length = wire_len & ~BURST_BIT
        duplicate = seq == tr.last_seq
        # A duplicate is read and thrown away, so the room left does not apply
        # to it - the block it repeats is already counted in that room.
        too_long = length > (MAX_BLOCK if duplicate else max_len)
        if (
            not _valid_type(typ)
            or not (duplicate or seq == tr.next_seq)
            or too_long
            or (burst and (not tr.burst_ok or not length or length % 256))
        ):
            o.byte_out(LINK_ABORT)  # the header slot is a single answer
            _abort_flood(o, max_len + FLOOD_MARGIN)
            return (RC_BUFOVFLW if too_long else RC_PROTOERR), None, None

        if burst:
            rc, payload = o.burst_recv(length)  # the header ACK is the GO byte
        else:
            if o.byte_out(LINK_ACK) != RC_SUCCESS:
                return RC_CONNERR, None, None
            rc, payload = o.read_payload(length) if length else (RC_SUCCESS, b"")
        if rc != RC_SUCCESS:
            return RC_CONNERR, None, None
        rc, c = o.read_payload(2)
        if rc != RC_SUCCESS:
            return RC_CONNERR, None, None
        if link_crc(payload) != c[0] | (c[1] << 8):
            if not nak():
                return RC_PROTOERR, None, None
            continue
        if not answer(LINK_ACK):
            return RC_CONNERR, None, None
        if duplicate:
            naks = 0  # the limit is per block, and the next one is a new block
            continue  # the sender missed our ACK; it moves on now
        tr.last_seq = seq
        tr.next_seq = (seq + 1) & 0xFF
        return RC_SUCCESS, typ, bytes(payload)


def link2_send_block(
    tr: Transfer, payload: bytes | bytearray, typ: int, burst: bool = False
) -> int:
    """Send one block to the MSX.  Returns RC_SUCCESS once it is ACKed, RC_PROTOERR
    when the MSX aborts or the safety cap is reached."""
    o = _io()
    payload = bytes(payload)
    if len(payload) > MAX_BLOCK:
        return RC_BUFOVFLW
    burst = (
        burst and tr.burst_ok and bool(payload) and not len(payload) % 256
    )
    seq = tr.send_seq
    crc = link_crc(payload)
    head = _hdr(typ, len(payload) | (BURST_BIT if burst else 0), seq)
    tail = bytes((crc & 0xFF, crc >> 8))
    for _ in range(LINK2_SENDER_CAP):
        rc = o.write_payload(head)
        if rc != RC_SUCCESS:
            return RC_CONNERR
        rc, a = o.byte_in()
        if rc != RC_SUCCESS:
            return RC_CONNERR
        if a in (LINK_ABORT, HELLO2):
            # HELLO2: the MSX has given this transfer up and is opening the next
            return RC_PROTOERR
        if a == LINK_NAK:
            continue  # resend the header
        # ACK, or garbled: a receiver NAKs only after a fault of its own, so an
        # ACK that arrives damaged is far likelier than a NAK that does, and
        # resending the header to a receiver that is already waiting for the
        # payload would put the two ends out of step.
        if burst:
            rc = o.burst_send(payload)  # GO + payload, one run
        else:
            rc = o.write_payload(payload) if payload else RC_SUCCESS
        if rc != RC_SUCCESS:
            return RC_CONNERR
        rc = o.write_payload(tail)
        if rc != RC_SUCCESS:
            return RC_CONNERR
        rc, a = o.read_payload(2 if typ != RC_READY else 1)
        if rc != RC_SUCCESS:
            return RC_CONNERR
        if LINK_ACK in a:
            tr.send_seq = (seq + 1) & 0xFF
            return RC_SUCCESS
        if LINK_ABORT in a or HELLO2 in a:
            return RC_PROTOERR
        # NAK or anything else: resend the whole block, same seq
    return RC_PROTOERR


def link2_recv(
    tr: Transfer, maxbufsize: int = 8192
) -> Tuple[int, Optional[bytes]]:
    """A whole transfer from the MSX: blocks until one whose type is not RC_READY."""
    data = bytearray()
    block_max = min(tr.msx_size or MAX_BLOCK, MAX_BLOCK)
    while True:
        # The room left goes into the header check, so a block that does not fit
        # is ABORTed in its header slot.  Checking after the block had been ACKed
        # told the MSX the transfer had succeeded while this side dropped it.
        rc, typ, payload = link2_recv_block(tr, min(block_max, maxbufsize - len(data)))
        if rc != RC_SUCCESS:
            return rc, None
        data.extend(payload)
        if typ != RC_READY:
            return RC_SUCCESS, bytes(data)


def link2_send(
    tr: Transfer, payload: bytes | bytearray, header_rc: Optional[int] = None
) -> int:
    """A whole transfer to the MSX, in blocks no larger than the MSX accepts."""
    payload = bytes(payload)
    size = min(tr.msx_size or MAX_BLOCK, MAX_BLOCK)
    offset = 0
    while True:
        end = min(offset + size, len(payload))
        last = end >= len(payload)
        # An explicit header_rc only ever tags the last block: the MSX takes any
        # type other than RC_READY as "last".
        typ = (RC_SUCCESS if header_rc is None else header_rc) if last else RC_READY
        rc = link2_send_block(tr, payload[offset:end], typ, burst=True)
        if rc != RC_SUCCESS:
            return rc
        if last:
            return RC_SUCCESS
        offset = end
