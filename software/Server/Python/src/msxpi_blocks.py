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

from __future__ import annotations

# Standard library imports
from typing import Optional, Tuple
import logging

# Third-party imports

from msxpi_settings import TMPDIR

logger = logging.getLogger("msxpi")

from msxpi_const import (
    BURST_FLAG,
    GLOBALRETRIES,
    MAX_BLOCK_RETRIES,
    RC_BUFOVFLW,
    RC_CHKSUM_ERR,
    RC_CONNERR,
    RC_FAILED,
    RC_HANDSHAKEERR,
    RC_INVALIDDATASIZE,
    RC_READY,
    RC_SUCCESS,
    READY,
    READY_ACK,
)
from msxpi_ethglue import eth_handle_opcode
from msxpi_transport import (
    SPI_BurstIn,
    SPI_BurstOut,
    SPI_ByteTransfer,
    SPI_ReadPayload,
    SPI_WritePayload,
    burst_capable,
)


def pcopy_handshake() -> Tuple[int, int]:
    """Performs the initial handshake with MSX and receives msx_blocksize."""
    # Wait for READY from MSX
    while True:
        rc, byte = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return RC_HANDSHAKEERR, 0
        if byte == READY:
            break

    # Send READY_ACK back to MSX
    rc, _ = SPI_ByteTransfer(READY_ACK)
    if rc != RC_SUCCESS:
        return RC_HANDSHAKEERR, 0

    # Receive msx_blocksize (low byte, high byte)
    rc, low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_CONNERR, 0

    rc, high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_CONNERR, 0

    msx_blocksize = low | (high << 8)
    return RC_SUCCESS, msx_blocksize


def recvdata2(maxbufsize: int = 8192) -> Tuple[int, Optional[bytes]]:
    """
    Python-side counterpart of MSX SENDDATA2().
    Full block-based, multi-block protocol using SPI_ByteTransfer.

    Returns: (rc, payload_bytes) where:
      - rc is RC_SUCCESS or an error code
      - payload_bytes is bytes on success, or None on error
    """

    data = bytearray()
    expected_block_index = 0

    # -------------------------
    # 1. Initial handshake
    # MSX   -> READY
    # Python-> READY_ACK
    # MSX   -> msxmaxbuf_low, msxmaxbuf_high
    # -------------------------
    while True:
        rc, pibyte = SPI_ByteTransfer()
        # A closed TCP peer is permanent: recv() returns b'' at once, forever, so
        # retrying spins at full speed and floods the log. Only give up on that;
        # timeouts and noise still mean keep waiting.
        if rc == RC_CONNERR:
            return (RC_CONNERR, None)
        if rc != RC_SUCCESS:
            continue  # ignore transient SPI errors

        if pibyte == READY:
            # Send READY_ACK back
            SPI_ByteTransfer(READY_ACK)
            break
        elif eth_handle_opcode(pibyte):
            # An Ethernet UNAPI fast/bulk op (msxpi_eth.py).  It has already
            # been served in full and is not a command, so keep waiting for
            # READY rather than returning to the dispatch loop.  This branch
            # used to silently discard the byte, which is exactly why the
            # opcode range was chosen to live here.
            continue
        else:
            # Ignore garbage and keep waiting for READY
            continue

    # Receive msxmaxbuf (MSX advertised max bytes per block)
    rc, low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)
    rc, high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    msxmaxbuf = low | (high << 8)
    block_max = min(msxmaxbuf, maxbufsize)

    # -------------------------
    # 2. Block receive loop
    # -------------------------
    while True:
        # --- header_rc ---
        rc, header_rc = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # --- length low/high ---
        rc, size_low = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)
        rc, size_high = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        length = size_low | (size_high << 8)
        # Bit 15: the MSX sends this payload as a /WAIT burst (OTIR). It only
        # does so once this server has sent it a burst block, and never on a
        # retry - see senddata_oneblock and the ROM's DSKIO_TXSIZE.
        burst = bool(length & BURST_FLAG)
        length &= ~BURST_FLAG
        if burst and not globals().get("_burst_in_announced"):
            globals()["_burst_in_announced"] = True
            print("recvdata2(): MSX sends /WAIT burst payloads - receiving them")

        # --- block_index ---
        rc, block_index = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # Validate block index
        if block_index != expected_block_index:
            # Protocol drift
            print(
                f"recvdata2: block index {block_index}, expected {expected_block_index} "
                f"(header_rc {header_rc:#04x}, len {length}, burst {burst}) - out of step"
            )
            return (RC_CONNERR, None)

        # Capacity checks
        if length > block_max:
            # MSX tried to send more than negotiated / allowed
            print(
                f"recvdata2: block of {length} bytes exceeds the negotiated {block_max}"
            )
            return (RC_CONNERR, None)
        if len(data) + length > maxbufsize:
            # Would overflow caller's max buffer
            print(
                f"recvdata2: {len(data)}+{length} bytes exceeds the {maxbufsize}-byte buffer"
            )
            return (RC_CONNERR, None)

        # --- Payload ---
        rc, payload = SPI_BurstIn(length) if burst else SPI_ReadPayload(length)
        if rc != RC_SUCCESS:
            print(
                f"recvdata2: payload read failed rc={rc:#04x} "
                f"({'burst' if burst else 'polled'}, block {block_index}, {length} bytes)"
            )
            return (RC_CONNERR, None)
        chksum = sum(payload)

        # --- Local checksum (Python receiver) ---
        right = chksum & 0xFF
        left = (chksum >> 8) & 0xFF
        local_sum = (right + left) & 0xFF

        # --- Receive MSX checksum ---
        rc, msxsum = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            print(f"recvdata2: reading the MSX checksum failed rc={rc:#04x}")
            return (RC_CONNERR, None)

        # --- Send local checksum back ---
        SPI_ByteTransfer(local_sum)

        # --- Compare checksums ---
        if msxsum != local_sum:
            # Checksum mismatch:
            # - DO NOT commit payload
            # - DO NOT advance expected_block_index
            # - DO NOT do status handshake
            # MSX will detect mismatch and resend this block.
            # Logged because it used to be silent: after GLOBALRETRIES failed
            # resends the MSX gives up with "Disk error writing" while this
            # loop is still waiting for a header, and the next command's bytes
            # then fail the block-index check - so a real checksum problem only
            # ever showed up as "dskiowrs: checksum error" with no cause.
            print(
                f"recvdata2: checksum mismatch, block {block_index}, {length} bytes, "
                f"{'burst' if burst else 'polled'}: MSX {msxsum:#04x}, Pi {local_sum:#04x} - MSX resends"
            )
            # DIAGNOSTIC (not for release): keep what a failed burst delivered,
            # to line it up against the source file - a duplicated byte shows
            # as a repeat at one offset, line noise as changed bits.
            if burst:
                try:
                    n = globals().get("_burst_dump_n", 0) + 1
                    globals()["_burst_dump_n"] = n
                    dump = f"{TMPDIR}/msxpi-burst-mismatch-{n}.bin"
                    with open(dump, "wb") as f:
                        f.write(bytes(payload))
                    print(f"recvdata2: received burst payload saved to {dump}")
                except OSError as e:
                    print(f"recvdata2: could not save the burst payload: {e}")
            continue

        # Checksums match: commit block
        data.extend(payload)
        expected_block_index += 1

        # -------------------------
        # 3. Status handshake after GOOD block
        #
        #   Python -> READY
        #   Python -> status_for_next (RC_SUCCESS / error)
        #   MSX    -> READY_ACK
        # -------------------------

        status_for_next = RC_SUCCESS  # for now, always success

        # Send READY (ignore returned byte)
        SPI_ByteTransfer(READY)

        # Send status_for_next (ignore returned byte)
        SPI_ByteTransfer(status_for_next)

        # Expect READY_ACK from MSX
        rc, ack = SPI_ByteTransfer()
        if rc != RC_SUCCESS or ack != READY_ACK:
            print(
                f"recvdata2: status handshake failed after block {block_index} "
                f"(rc={rc:#04x}, got {ack!r}, want READY_ACK {READY_ACK:#04x})"
            )
            return (RC_HANDSHAKEERR, None)

        # If this was the last block, we're done
        if header_rc == RC_SUCCESS:
            return (RC_SUCCESS, bytes(data))

        # Otherwise header_rc == RC_READY: loop for next block


def senddata(header_rc: int, payload: bytes | bytearray) -> int:
    """
    Python-side counterpart of MSX RECVDATA2().

    Protocol (final design):

      Initial handshake (before first block):
        MSX   -> READY
        Python-> READY_ACK
        MSX   -> msxmaxbuf_low, msxmaxbuf_high   (max payload bytes per block)

      For each block (block_index = 0..255, wraps):
        Python sends:
          [header_rc]    RC_READY / RC_SUCCESS / RC_CHKSUM_ERR
          [size_low]
          [size_high]
          [block_index]  (same on retries)
          [payload bytes...]
          [checksum]     (collapsed checksum of payload bytes only)

        MSX sends:
          [checksum]     (its own computed checksum for this block)

        Python:
          - If local checksum != MSX checksum:
              Retry same block up to GLOBALRETRIES,
              with header_rc = RC_CHKSUM_ERR on retries.
              If still failing -> return RC_CHKSUM_ERR.

          - If checksums match:
              Wait for status handshake about this block:

                MSX   -> READY
                MSX   -> status_byte (RC_SUCCESS / RC_CHKSUM_ERR)
                Python-> READY_ACK

              If status_byte == RC_CHKSUM_ERR:
                  MSX rejected the block, resend same block (same index, same data).
              If status_byte == RC_SUCCESS:
                  Commit block: advance offset and block_index.

      Termination:
        When all payload bytes are committed (offset >= total_size)
        and last status from MSX was RC_SUCCESS:
          -> return RC_SUCCESS

      Return codes:
        RC_SUCCESS    - All blocks sent and acknowledged by MSX.
        RC_CHKSUM_ERR - Unrecoverable checksum failure after retries.
        RC_FAILED     - SPI/protocol failure (unexpected byte, transfer error, etc.).

      Notes:
        - 'header_rc' parameter is kept for API compatibility but is NOT used.
          The function decides header_rc per block as:
            RC_READY      when more blocks will follow,
            RC_SUCCESS    when this is the last block (on first attempt),
            RC_CHKSUM_ERR on Python-side retries.
    """

    total_size = len(payload)
    offset = 0
    block_index = 0  # 0..255, wraps

    # -------------------------
    # Helper: compute collapsed checksum of a bytes-like block
    # -------------------------
    def compute_checksum(block_bytes):
        s = 0
        for b in block_bytes:
            if not isinstance(b, int):
                b = ord(b)
            s += b
        right = s & 0xFF
        left = (s >> 8) & 0xFF
        return (right + left) & 0xFF

    # -------------------------
    # Helper: wait for MSX READY + status, then ACK
    # Used after each successfully transmitted block
    # -------------------------
    def wait_status_handshake():
        """
        Waits for:
          MSX -> READY
          MSX -> status_byte  (RC_SUCCESS / RC_CHKSUM_ERR)
        Sends:
          Python -> READY_ACK

        Returns:
          (RC_SUCCESS, status_byte) on success
          (RC_FAILED, None)        on SPI/protocol failure
        """
        # Wait for READY
        while True:
            rc, b = SPI_ByteTransfer()
            # A closed TCP peer is permanent: recv() returns b'' at once, forever, so
            # retrying spins at full speed and floods the log. Only give up on that;
            # timeouts and noise still mean keep waiting.
            if rc == RC_CONNERR:
                return (RC_FAILED, None)
            if rc != RC_SUCCESS:
                # SPI error: keep waiting; higher-level timeout policy is outside this function
                continue
            if b == READY:
                break
            print(f"Status handshake: expected READY, got {b}")

        # Read status byte
        rc, status = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            print("Status handshake: failed to read status byte from MSX")
            return (RC_FAILED, None)

        # Send READY_ACK
        SPI_ByteTransfer(READY_ACK)
        print(f"Status handshake: MSX status={status}")
        return (RC_SUCCESS, status)

    # -------------------------
    # 1. Initial handshake
    # -------------------------
    while True:
        rc, pibyte = SPI_ByteTransfer()
        # A closed TCP peer is permanent: recv() returns b'' at once, forever, so
        # retrying spins at full speed and floods the log. Only give up on that;
        # timeouts and noise still mean keep waiting.
        if rc == RC_CONNERR:
            return RC_CONNERR
        if rc != RC_SUCCESS:
            # SPI error: ignore and keep waiting
            continue
        if pibyte == READY:
            print("Handshake: Detected READY from MSX (initial)")
            SPI_ByteTransfer(READY_ACK)
            print("Handshake: Sent READY_ACK to MSX (initial)")
            break
        print(f"Handshake: expected READY, got {pibyte}")

    # Receive msxmaxbuf (maximum payload bytes per block)
    rc, msxmaxbuf_low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        print("senddata: failed to read msxmaxbuf_low")
        return RC_FAILED

    rc, msxmaxbuf_high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        print("senddata: failed to read msxmaxbuf_high")
        return RC_FAILED

    msxmaxbuf = msxmaxbuf_low | (msxmaxbuf_high << 8)
    print(f"senddata: This block size = {msxmaxbuf}")

    # -------------------------
    # 2. Block send loop
    # -------------------------
    while True:
        # All data committed?
        if offset >= total_size:
            print("senddata: all blocks committed, transfer complete")
            return RC_SUCCESS

        # Build block from current offset
        remaining = total_size - offset
        block_size = msxmaxbuf if remaining > msxmaxbuf else remaining
        block_bytes = payload[offset : offset + block_size]
        local_sum = compute_checksum(block_bytes)

        is_last_block = offset + block_size >= total_size
        # First attempt header: RC_SUCCESS if last, else RC_READY
        base_header = RC_SUCCESS if is_last_block else RC_READY

        print(
            f"senddata: preparing block index={block_index}, "
            f"offset={offset}, size={block_size}, checksum={local_sum}, "
            f"is_last_block={is_last_block}"
        )

        # 2a. Send this block with Python-side checksum retries
        retries = 0
        while True:
            # On retries (Python-side checksum mismatch), use RC_CHKSUM_ERR
            header_for_this_try = base_header if retries == 0 else RC_CHKSUM_ERR

            # --- Send header_rc ---
            rc, _ = SPI_ByteTransfer(header_for_this_try & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending header_rc")
                return RC_FAILED

            # --- Send size (low, high) ---
            rc, _ = SPI_ByteTransfer(block_size & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending size_low")
                return RC_FAILED

            rc, _ = SPI_ByteTransfer((block_size >> 8) & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending size_high")
                return RC_FAILED

            # --- Send block index (1 byte, wraps naturally) ---
            rc, _ = SPI_ByteTransfer(block_index & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending block_index")
                return RC_FAILED

            # --- Send payload bytes ---
            rc = SPI_WritePayload(block_bytes)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending payload")
                return RC_FAILED

            # --- Send checksum ---
            rc, _ = SPI_ByteTransfer(local_sum & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending checksum")
                return RC_FAILED

            print(
                f"senddata: sent block index={block_index}, size={block_size}, "
                f"header_rc={header_for_this_try}, checksum={local_sum}"
            )

            # --- Receive MSX checksum for this block ---
            rc, msxsum = SPI_ByteTransfer()
            if rc != RC_SUCCESS:
                print("senddata: failed to receive checksum from MSX")
                return RC_FAILED

            print(f"senddata: received MSX checksum={msxsum}")

            if msxsum == local_sum:
                print("senddata: local/MSX checksum match (Python-side OK)")
                # Python is satisfied; MSX will confirm via status handshake.
                break

            print("senddata: checksum mismatch (Python-side), will retry block")
            retries += 1
            if retries >= GLOBALRETRIES:
                print("senddata: too many checksum retries, aborting")
                return RC_CHKSUM_ERR
            # Loop again: re-send same block with header_rc=RC_CHKSUM_ERR

        # 2b. Wait for MSX status handshake about this block
        rc, status = wait_status_handshake()
        if rc != RC_SUCCESS:
            return RC_FAILED

        if status == RC_CHKSUM_ERR:
            # MSX rejected this block; resend exact same block.
            print(
                f"senddata: MSX reported checksum error for block index={block_index}, "
                "will resend same block"
            )
            # Do NOT advance offset or block_index.
            # Loop will rebuild same block from same offset.
            continue

        if status == RC_SUCCESS:
            # MSX accepted this block; commit it.
            print(
                f"senddata: MSX accepted block index={block_index}, "
                f"committing size={block_size}"
            )
            offset += block_size
            block_index = (block_index + 1) & 0xFF
            # Loop back: if more data remains, build next block.
            continue

        print(f"senddata: unexpected MSX status={status}, aborting")
        return RC_FAILED

    MAX_BLOCK_RETRIES = 3


def recvdata2_oneblock(maxbufsize: int) -> Tuple[int, Optional[bytes]]:
    """
    Python counterpart of RECVDATA2_ONEBLOCK().
    Reads exactly ONE block sent by MSX.

    Returns: (rc, payload_bytes)
      rc = RC_SUCCESS  → last block
      rc = RC_READY    → more blocks will follow
      rc = RC_CHKSUM_ERR → checksum mismatch after retries
      rc = RC_CONNERR / RC_HANDSHAKEERR → protocol failure
    """

    # -------------------------
    # 1. Initial handshake
    # MSX -> READY
    # Python -> READY_ACK
    # MSX -> msxmaxbuf_low, msxmaxbuf_high
    # -------------------------

    while True:
        rc, byte = SPI_ByteTransfer()
        # A closed TCP peer is permanent: recv() returns b'' at once, forever, so
        # retrying spins at full speed and floods the log. Only give up on that;
        # timeouts and noise still mean keep waiting.
        if rc == RC_CONNERR:
            return (RC_CONNERR, None)
        if rc != RC_SUCCESS:
            continue  # ignore transient SPI noise

        if byte == READY:
            SPI_ByteTransfer(READY_ACK)
            break
        # ignore garbage and continue waiting

    # Receive msxmaxbuf
    rc, low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    rc, high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    msxmaxbuf = low | (high << 8)
    block_max = min(msxmaxbuf, maxbufsize)

    # -------------------------
    # 2. Read exactly one block - header INCLUDED in each attempt
    # -------------------------
    # SENDDATA2 resends the WHOLE block on a checksum mismatch: header_rc,
    # length, index, payload and checksum.  That is also what
    # senddata_oneblock() does when Python is the sender, and what
    # RECVDATA_ONEBLOCK expects when the MSX receives - so the header must be
    # re-read here on every attempt.
    #
    # Reading it once, outside the loop, made a single corrupted byte fatal:
    # the MSX resent its four header bytes, this loop consumed them as the
    # first four payload bytes, everything shifted by four, and every retry
    # failed the same way.  After MAX_BLOCK_RETRIES the stream was so far out
    # of step that the connection died and the server reinitialised over and
    # over - seen on hardware about forty blocks into a 512 KB upload, where
    # the retry should have absorbed one bad byte invisibly.
    attempts = 0

    while True:
        # --- header_rc ---
        rc, header_rc = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # --- length low/high ---
        rc, lo = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        rc, hi = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        length = lo | (hi << 8)

        if length > block_max:
            return (RC_BUFOVFLW, None)

        # --- block_index ---
        rc, block_index = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # For one-block variant, MSX enforces index = 0
        if block_index != 0:
            return (RC_CONNERR, None)

        rc, payload = SPI_ReadPayload(length)
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)
        chksum = sum(payload)

        # Local checksum
        right = chksum & 0xFF
        left = (chksum >> 8) & 0xFF
        local_sum = (right + left) & 0xFF

        # Receive MSX checksum
        rc, msxsum = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # Send our checksum back
        SPI_ByteTransfer(local_sum)

        if msxsum == local_sum:
            # Block accepted
            break

        attempts += 1
        if attempts >= MAX_BLOCK_RETRIES:
            return (RC_CHKSUM_ERR, None)

        # Otherwise MSX will resend the same block; loop again

    # -------------------------
    # 3. Status handshake after GOOD block
    #
    # The RECEIVER sends READY and the status, and the SENDER answers
    # READY_ACK.  That is what the MSX does when IT receives (RECVDATA_ONEBLOCK
    # in msxpi_bios.asm) and what senddata_oneblock() expects when Python
    # sends, so here - with Python receiving - Python must send:
    #
    #   Python -> READY
    #   Python -> status_for_next
    #   MSX    -> READY_ACK
    #
    # This used to be written the other way round, with Python waiting for a
    # READY the MSX was never going to send: both ends read, and the transfer
    # died at the very last step with RC_HANDSHAKEERR - after the payload had
    # arrived intact, which the caller then threw away.  It went unnoticed
    # because nothing sent bulk data from the MSX to the Pi until pcopy learned
    # to upload.
    # -------------------------

    SPI_ByteTransfer(READY)
    SPI_ByteTransfer(RC_SUCCESS)

    rc, ack = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_HANDSHAKEERR, None)
    if ack != READY_ACK:
        return (RC_HANDSHAKEERR, None)

    # -------------------------
    # 4. Interpret header_rc
    # -------------------------

    if header_rc == RC_SUCCESS:
        return (RC_SUCCESS, bytes(payload))  # last block

    if header_rc == RC_READY:
        return (RC_READY, bytes(payload))  # more blocks coming

    return (RC_CONNERR, None)  # unexpected header


def senddata_oneblock(
    payload: bytes,
    msx_blocksize: int,
    header_rc: int,
    block_index: int = 0,
    burst: bool = False,
) -> int:
    length = len(payload)
    if length > msx_blocksize:
        return RC_INVALIDDATASIZE
    # A burst block says so in bit 15 of its length; the MSX then reads the
    # payload with /WAIT (INIR) instead of byte by byte. Only when it asked,
    # and only for whole 256-byte runs (a 512-byte sector): the ROM's burst
    # loop has no room for a remainder. Anything else goes byte by byte.
    wire_length = (
        length | BURST_FLAG if burst and length and not length % 256 else length
    )

    # 1. Initial handshake: MSX -> READY, Python -> READY_ACK
    # Is performed by sendmultiblock() once before calling this function.

    # 2. Send exactly one block with retries
    attempts = 0
    while True:
        # header_rc
        rc, _ = SPI_ByteTransfer(header_rc)
        if rc != RC_SUCCESS:
            return RC_CONNERR

        # length low/high
        rc, _ = SPI_ByteTransfer(wire_length & 0xFF)
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending length low byte")
            return RC_CONNERR
        rc, _ = SPI_ByteTransfer((wire_length >> 8) & 0xFF)
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending length high byte")
            return RC_CONNERR

        # block_index
        rc, _ = SPI_ByteTransfer(block_index & 0xFF)
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending block_index")
            return RC_CONNERR

        # payload
        chksum = sum(payload)
        rc = (
            SPI_BurstOut(payload)
            if wire_length & BURST_FLAG
            else SPI_WritePayload(payload)
        )
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending payload")
            return RC_CONNERR

        # local checksum
        right = chksum & 0xFF
        left = (chksum >> 8) & 0xFF
        local_sum = (right + left) & 0xFF

        # send checksum
        rc, _ = SPI_ByteTransfer(local_sum)
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending local checksum")
            return RC_CONNERR

        # receive MSX checksum
        rc, msxsum = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED receiving MSX checksum")
            return RC_CONNERR

        if msxsum == local_sum:
            # block accepted
            break

        attempts += 1
        if attempts >= MAX_BLOCK_RETRIES:
            return RC_CHKSUM_ERR
        # else: loop and resend entire block

    # 3. Status handshake after GOOD block
    # MSX (receiver) does: READY, status_for_next, expects READY_ACK.
    # Python (sender) must: read READY, read status, send READY_ACK.
    rc, ready = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_HANDSHAKEERR
    if ready != READY:
        return RC_HANDSHAKEERR

    rc, status_from_msx = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_CONNERR
    if status_from_msx != RC_SUCCESS:
        return RC_CONNERR

    # send READY_ACK
    SPI_ByteTransfer(READY_ACK)

    # 4. Interpret header_rc (what we told MSX)
    if header_rc == RC_SUCCESS:
        return RC_SUCCESS  # last block
    if header_rc == RC_READY:
        return RC_READY  # more blocks follow
    return RC_CONNERR  # unexpected header


def PerformHandshake() -> Tuple[int, int]:
    # 1. Initial handshake: MSX -> READY, Python -> READY_ACK
    while True:
        rc, byte = SPI_ByteTransfer()
        # A closed TCP peer is permanent: recv() returns b'' at once, forever, so
        # retrying spins at full speed and floods the log. Only give up on that;
        # timeouts and noise still mean keep waiting.
        if rc == RC_CONNERR:
            return RC_CONNERR, 0
        if rc != RC_SUCCESS:
            continue  # ignore noise
        if byte == READY:
            SPI_ByteTransfer(READY_ACK)
            break
        else:
            print(
                f"PerformHandshake(): discarded stray byte {hex(byte)} while waiting for READY"
            )

    # Receive msx_blocksize
    rc, low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_CONNERR, 0
    rc, high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_CONNERR, 0

    msx_blocksize = low | (high << 8)

    return RC_SUCCESS, msx_blocksize


def sendmultiblock(payload: bytes, header_rc: Optional[int] = None) -> int:
    """
    Sends a large payload to the MSX in multiple blocks using senddata_oneblock().

    Returns:
      RC_SUCCESS  → all blocks sent, last block acknowledged
      RC_CONNERR / RC_HANDSHAKEERR / RC_CHKSUM_ERR → protocol failure
    """

    total_len = len(payload)
    if total_len == 0:
        return RC_INVALIDDATASIZE  # or RC_SUCCESS if you want to allow empty transfers

    # Perform handshake for each block
    # Moved here to allow dynamic msx_blocksize per block,
    # Set by MSX each time.
    rc, msx_blocksize = PerformHandshake()
    if rc != RC_SUCCESS:
        return rc
    # Bit 15 of the block size is the MSX asking for /WAIT burst payloads.
    # Honour it only when this host can hold READY for a whole block; either
    # way it is not part of the size.
    burst = bool(msx_blocksize & BURST_FLAG) and burst_capable()
    msx_blocksize &= ~BURST_FLAG
    if burst and not globals().get("_burst_announced"):
        globals()["_burst_announced"] = True
        print("sendmultiblock(): MSX asked for /WAIT burst payloads - enabled")

    offset = 0
    block_index = 0
    while offset < total_len:

        # Determine slice for this block
        end = min(offset + msx_blocksize, total_len)
        block = payload[offset:end]

        # header_rc: RC_READY for intermediate blocks, RC_SUCCESS (or the
        # caller's override) for the last block. An explicit override must
        # NEVER apply to an intermediate block - the client's receive loop
        # (RECVDATA_ONEBLOCK/RECV_LOOP) uses "not RC_READY" as its signal
        # that a block is the last one, so tagging an early block with e.g.
        # RC_SUCCNOSTD would make the client stop receiving mid-transfer
        # while this loop keeps sending - a protocol desync. This is only
        # reachable when a payload spans more than one block; every current
        # caller of an explicit header_rc sends a single-block payload, so
        # for them "last block" and "first block" are the same block and
        # this is behaviorally identical to before.
        if end < total_len:
            block_rc = RC_READY
        elif not header_rc == None:
            block_rc = header_rc
        else:
            block_rc = RC_SUCCESS

        # Send one block
        rc = senddata_oneblock(block, msx_blocksize, block_rc, block_index, burst)
        if rc not in (RC_SUCCESS, RC_READY):
            # Any error aborts the whole transfer
            return rc

        # Advance to next block
        offset = end
        block_index += 1

    return RC_SUCCESS


def readParameters(errorMsg: str, needParm: bool = False) -> Tuple[int, Optional[str]]:
    rc, data = recvdata2()

    if rc != RC_SUCCESS:
        print(f"Pi:Error reading parameters")
        encodederrorMsg = ("Pi:Error reading parameters").encode()
        sendmultiblock(encodederrorMsg)
        return RC_FAILED, None

    parms = data.decode().split("\x00")[0].strip()
    if needParm and not parms:
        print(f"Pi:Error - {errorMsg}")
        encodederrorMsg = ("Pi:Error - " + errorMsg).encode()
        sendmultiblock(encodederrorMsg)
        return RC_FAILED, None

    return RC_SUCCESS, parms
