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
from typing import Callable, Iterable, Optional, Tuple
import time
import subprocess
import logging
import os
import platform
import socket

# Third-party imports
import mmap

logger = logging.getLogger("msxpi")

from msxpi_const import (
    RC_CONNERR,
    RC_FAILED,
    RC_SUCCESS,
    SYNCTRANSFTIMEOUT,
)

DISABLETIMEOUT = False  # Disable timeout checking (debug mode)
conn = None
# Set by msxpi-server.py at start-up: RPi.GPIO on a Pi, and the pin numbers
# from msxpi.ini.
GPIO = None
SPI_CS = SPI_SCLK = SPI_MOSI = SPI_MISO = RPI_READY = None

hostType = "RaspberryPi"
# Shutdown/reboot button GPIO, from "var RPI_SHUTDOWN=<gpio>" in msxpi.ini -
# see the main section.  None (the default) means no button: the pin is not
# even configured.
RPI_SHUTDOWN = None
press_time = None


def detect_host():
    system = platform.system()
    machine = platform.machine()

    if system == "Windows":
        return "Windows"
    elif system == "Darwin":
        return "MacOS"
    elif system == "Linux":
        # Check for Raspberry Pi
        try:
            with open("/proc/cpuinfo", "r") as f:
                cpuinfo = f.read()
            if (
                "Raspberry Pi" in cpuinfo
                or "BCM" in cpuinfo
                or "Raspberry" in platform.uname().node
            ):
                return "RaspberryPi"
        except Exception:
            pass
        return "Linux"
    else:
        return system


def init_spi_bitbang():
    # Pin Setup:
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(SPI_CS, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(SPI_SCLK, GPIO.OUT)
    GPIO.setup(SPI_MOSI, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
    GPIO.setup(SPI_MISO, GPIO.OUT)
    GPIO.setup(RPI_READY, GPIO.OUT)
    if RPI_SHUTDOWN is not None:
        GPIO.setup(RPI_SHUTDOWN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    _init_fast_gpio()


# =============================================================================
# CHANGE 1 + 2: faster GPIO path for the SPI bit-bang.
#
# CHANGE 1  The time.sleep(0.00001) that used to sit inside tick_sclk() is gone.
#           A 10 us sleep really costs 55-100 us on Linux (scheduler granularity),
#           and it was called twice per byte - roughly 140 us of the ~250 us that
#           a byte took.  The CPLD needs a clock pulse of a few NANOseconds; two
#           consecutive GPIO writes are already microseconds apart, so the sleep
#           bought nothing at all.
#
# CHANGE 2  The per-bit GPIO calls now go straight to the BCM GPIO registers
#           through /dev/gpiomem instead of through RPi.GPIO.  Each RPi.GPIO call
#           costs ~3 us of Python + C-extension overhead; a direct register write
#           costs ~0.2-0.3 us.  There are ~38 of them per byte.
#
# Deliberately NOT bypassed: pin direction, pull-ups and cleanup still go through
# RPi.GPIO.  Only the hot inner loop is fast-pathed.  That matters - the /WAIT
# safety story depends on GPIO.cleanup() releasing RPI_READY so the board's R8
# 10K pulldown can drag it low, and on SPI_CS keeping R9's pull-up.  Re-implementing
# direction/cleanup here would put that at risk for no measurable gain.
#
# Falls back to the original RPi.GPIO path automatically if anything is off:
# /dev/gpiomem missing or unreadable, a pin number >= 32, a Pi 5 (BCM2712/RP1 has
# a completely different GPIO block), or the self-test failing.  You can also
# force the old path for an A/B measurement:
#
#     MSXPI_SLOW_GPIO=1 ./msxpi-server.py
#
# BCM2835/6/7 and BCM2711 GPIO register offsets, as 32-bit word indices:
_GPSET0 = 0x1C >> 2  # write 1 to set   a pin high
_GPCLR0 = 0x28 >> 2  # write 1 to clear a pin low
_GPLEV0 = 0x34 >> 2  # read pin levels

_FAST_GPIO = False
_GPIO_REG = None
_NATIVE_GPIO = None

# ---------------------------------------------------------------------------
# Profiler.  Enable with MSXPI_PROFILE=1.  Answers one question: how much of the
# wall-clock time is actually spent inside SPI_ByteTransfer()?
#
# 8 KB in 9.6 s is ~1.17 ms/byte, but SPI_ByteTransfer() should be nowhere near
# that.  If "in transfer" comes back as a small fraction of elapsed, the cost is
# in the protocol/Python layers above, or in waiting for the MSX - and no amount
# of GPIO tuning will touch it.
_PROFILE = bool(os.environ.get("MSXPI_PROFILE"))
_prof_n = 0  # transfers completed
_prof_busy = 0.0  # seconds inside SPI_ByteTransfer, total
_prof_spin = 0.0  # of which: spinning on SPI_CS, i.e. waiting for the MSX
_prof_t0 = None  # wall clock at the first transfer
_PROF_EVERY = 1024


def _prof_report(force=False):
    if not _prof_n:
        return
    if not force and (_prof_n % _PROF_EVERY):
        return
    elapsed = time.perf_counter() - _prof_t0
    per = _prof_busy / _prof_n * 1e6
    spin = _prof_spin / _prof_n * 1e6
    print(
        f"[prof] {_prof_n} bytes | wall {elapsed:.2f}s "
        f"({elapsed / _prof_n * 1e6:.0f} us/byte) | "
        f"in SPI_ByteTransfer {_prof_busy:.2f}s ({per:.0f} us/byte, "
        f"{100.0 * _prof_busy / elapsed:.1f}% of wall) | "
        f"of which spinning on CS {spin:.0f} us/byte | "
        f"unaccounted {100.0 * (elapsed - _prof_busy) / elapsed:.1f}%"
    )


_M_SCLK = _M_MISO = _M_MOSI = _M_CS = _M_RDY = 0


def _init_fast_gpio():
    """Map /dev/gpiomem and verify it really drives this board's pins.

    Called from init_spi_bitbang(), i.e. after RPi.GPIO has set the directions
    and after the pin numbers have been read from the config file.
    """
    global _FAST_GPIO, _GPIO_REG, _NATIVE_GPIO
    global _M_SCLK, _M_MISO, _M_MOSI, _M_CS, _M_RDY

    _FAST_GPIO = False
    _NATIVE_GPIO = None

    if os.environ.get("MSXPI_SLOW_GPIO"):
        print(
            "init_fast_gpio(): MSXPI_SLOW_GPIO set - using the original RPi.GPIO path"
        )
        return

    pins = (SPI_SCLK, SPI_MISO, SPI_MOSI, SPI_CS, RPI_READY)
    if any(p is None or p < 0 or p > 31 for p in pins):
        print(f"init_fast_gpio(): pin(s) outside GPIO0-31 {pins} - staying on RPi.GPIO")
        return

    try:
        import ctypes

        fd = os.open("/dev/gpiomem", os.O_RDWR | os.O_SYNC)
        try:
            mm = mmap.mmap(
                fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0
            )
        finally:
            os.close(fd)
        reg = (ctypes.c_uint32 * 1024).from_buffer(mm)

        m_rdy = 1 << RPI_READY

        # Self-test: drive RPI_READY through the register window and read it back
        # through RPi.GPIO.  If the offsets or the SoC are wrong this fails here
        # rather than silently corrupting every transfer.
        reg[_GPSET0] = m_rdy
        hi_ok = GPIO.input(RPI_READY) == 1
        reg[_GPCLR0] = m_rdy
        lo_ok = GPIO.input(RPI_READY) == 0
        if not (hi_ok and lo_ok):
            raise RuntimeError(f"register self-test failed (high={hi_ok} low={lo_ok})")

        _GPIO_REG = reg
        _M_SCLK = 1 << SPI_SCLK
        _M_MISO = 1 << SPI_MISO
        _M_MOSI = 1 << SPI_MOSI
        _M_CS = 1 << SPI_CS
        _M_RDY = m_rdy
        _FAST_GPIO = True
        print("init_fast_gpio(): direct /dev/gpiomem path active (self-test passed)")

    except Exception as e:
        print(f"init_fast_gpio(): falling back to RPi.GPIO ({e})")
        _FAST_GPIO = False

    if _FAST_GPIO and os.environ.get("MSXPI_NATIVE_GPIO") == "1":
        try:
            from msxpi_gpio_native import NativeGPIO

            native = NativeGPIO(_GPIO_REG, (_M_SCLK, _M_MISO, _M_MOSI, _M_CS, _M_RDY))
            # msxpi_gpio_native.py is a separate file, and a Pi can end up
            # running this server with an older copy of it. One without
            # read_burst sends burst READS fine (the ROM then starts bursting
            # its writes) but raises AttributeError on the first burst WRITE -
            # outside the OSError the burst paths catch - so the server
            # answered mid-sector with an error string and every COPY to an
            # MSXPi drive failed with "Disk error writing". Only use an engine
            # that can burst both ways; the Python GPIO path below does.
            missing = [
                m
                for m in ("read", "write", "read_burst", "write_burst")
                if not callable(getattr(native, m, None))
            ]
            if missing:
                raise AttributeError(
                    f"msxpi_gpio_native.py is out of date, no {', '.join(missing)} "
                    f"- run update.sh"
                )
            _NATIVE_GPIO = native
            print(
                f"init_fast_gpio(): native GPIO payload engine active "
                f"(half-period {_NATIVE_GPIO.half_period_ns} ns, "
                f"CS setup {getattr(_NATIVE_GPIO, 'cs_setup_ns', 0)} ns)"
            )
        except (OSError, ValueError, ImportError, AttributeError) as e:
            print(
                f"init_fast_gpio(): native engine unavailable ({e}); using Python GPIO"
            )


def _spi_byte_fast(byte_out=None):
    """Bit-identical to the RPi.GPIO loop below, straight to the registers.

    Same edge map the CPLD expects and msxpi-server has always produced:
      leading tick, 8 data bits (MSB first, MOSI sampled while SCLK is high),
      trailing tick.
    """
    reg = _GPIO_REG
    SET = _GPSET0
    CLR = _GPCLR0
    LEV = _GPLEV0
    m_sclk = _M_SCLK
    m_miso = _M_MISO
    m_mosi = _M_MOSI

    byte_in = 0

    global _prof_n, _prof_busy, _prof_spin, _prof_t0
    if _PROFILE:
        _t_enter = time.perf_counter()
        if _prof_t0 is None:
            _prof_t0 = _t_enter

    reg[SET] = _M_RDY  # RPI_READY high
    while reg[LEV] & _M_CS:  # spin until the CPLD asserts CS
        pass

    if _PROFILE:
        _t_spun = time.perf_counter()

    reg[SET] = m_sclk  # leading tick
    reg[CLR] = m_sclk

    for bit in (0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01):
        if byte_out is not None and (byte_out & bit):
            reg[SET] = m_miso
        else:
            reg[CLR] = m_miso  # passive receive drives MISO low
        reg[SET] = m_sclk
        if reg[LEV] & m_mosi:
            byte_in |= bit
        reg[CLR] = m_sclk

    reg[SET] = m_sclk  # trailing tick
    reg[CLR] = m_sclk
    reg[CLR] = _M_RDY  # RPI_READY low

    if _PROFILE:
        _t_done = time.perf_counter()
        _prof_n += 1
        _prof_busy += _t_done - _t_enter
        _prof_spin += _t_spun - _t_enter
        _prof_report()

    return RC_SUCCESS, byte_in


def burst_capable() -> bool:
    """True when SPI_BurstOut can hold READY for a whole block (or no READY: TCP)."""
    return hostType != "RaspberryPi" or _NATIVE_GPIO is not None or _FAST_GPIO


# How long to wait for the MSX to collect a burst before giving up on it.
# Generous next to a per-byte time of tens of microseconds, but short enough
# that an abandoned burst cannot wedge the server.
BURST_CS_TIMEOUT = 0.25  # seconds


# -----------------------------------------------------------------------------
# openMSX link: "virtual SPI" over TCP
# -----------------------------------------------------------------------------
# The openMSX MSXPiDevice emulates the CPLD v1.6 at port level, so the TCP link
# carries what the GPIO pins carry on a Pi: every transfer is one full-duplex
# byte that the Pi offers (READY up + its MISO byte) and the CPLD clocks when
# the MSX starts a transfer (its MOSI byte). Two-byte frames:
#
#   server -> openMSX   01 d   offer d; READY drops after this transfer
#                       02 d   offer d; READY stays up for the next offer
#                       03 00  cancel offers not clocked yet
#                       7E v   hello, protocol version v
#   openMSX -> server   01 m   one offer was clocked, the CPLD sent m
#                       03 00  cancel acknowledged
#                       7E v   hello reply
#
# A run of 02 offers must be closed by a 01 offer in the same write: openMSX
# only makes the run visible once the closing offer is in.  An openMSX without
# CPLD emulation does not answer the hello; the link then stays raw bytes.
TCP_OP_OFFER = 0x01
TCP_OP_HOLD = 0x02
TCP_OP_CANCEL = 0x03
TCP_OP_HELLO = 0x7E
TCP_PROTOCOL_VERSION = 1
TCP_HELLO_TIMEOUT = 1.0  # seconds for openMSX to answer the hello
TCP_BURST_TIMEOUT = 10.0  # emulation can run slower than real time
_tcp_framed = False
_tcp_rx = bytearray()  # received but not yet consumed


def tcp_handshake(c: socket.socket) -> bool:
    """Greet a new openMSX connection; True when it speaks virtual SPI."""
    global _tcp_framed, _tcp_rx
    _tcp_framed = False
    _tcp_rx = bytearray()
    try:
        c.sendall(bytes((TCP_OP_HELLO, TCP_PROTOCOL_VERSION)))
        c.settimeout(TCP_HELLO_TIMEOUT)
        while len(_tcp_rx) < 2:
            chunk = c.recv(2 - len(_tcp_rx))
            if not chunk:
                break
            _tcp_rx.extend(chunk)
    except socket.timeout:
        pass
    if len(_tcp_rx) == 2 and _tcp_rx[0] == TCP_OP_HELLO:
        _tcp_framed = True
        _tcp_rx = bytearray()
        print(" ** openMSX link: virtual SPI (CPLD v1.6 emulation) **")
    else:
        # anything received is MSX data from an old device: keep it
        print(" ** openMSX link: raw bytes (openMSX without CPLD emulation) **")
    return _tcp_framed


def _tcp_frame(timeout):
    """Next two-byte frame from openMSX; raises socket.timeout/ConnectionError."""
    conn.settimeout(timeout)
    while len(_tcp_rx) < 2:
        chunk = conn.recv(4096)
        if not chunk:
            raise ConnectionError("connection closed by peer")
        _tcp_rx.extend(chunk)
    op, arg = _tcp_rx[0], _tcp_rx[1]
    del _tcp_rx[:2]
    return op, arg


def _tcp_cancel(got, count):
    """Withdraw the offers openMSX has not clocked; keeps the ones it did."""
    try:
        conn.sendall(bytes((TCP_OP_CANCEL, 0)))
        while True:
            op, arg = _tcp_frame(TCP_BURST_TIMEOUT)
            if op == TCP_OP_CANCEL:
                break
            if op == TCP_OP_OFFER:
                got.append(arg)
    except (socket.timeout, OSError, ConnectionError):
        return RC_CONNERR, None
    if len(got) == count:
        return RC_SUCCESS, got  # the last one landed while cancelling
    return RC_FAILED, None


def tcp_exchange(
    misos: Iterable[int], timeout: Optional[float], hold: bool = True
) -> Tuple[int, Optional[bytearray]]:
    """Offer bytes the way the Pi does, one CPLD transfer per byte.  hold=True
    keeps READY up across the run (a burst); hold=False drops READY after every
    byte, as SPI_ByteTransfer does, but still sends all offers in one write so
    a payload costs one round trip instead of one per byte.
    Returns (rc, the bytes the CPLD sent)."""
    count = len(misos)
    got = bytearray()
    if not count:
        return RC_SUCCESS, got
    frames = bytearray()
    for i, b in enumerate(misos):
        frames.append(TCP_OP_OFFER if i == count - 1 or not hold else TCP_OP_HOLD)
        frames.append(b & 0xFF)
    try:
        conn.sendall(frames)
        while len(got) < count:
            op, arg = _tcp_frame(timeout)
            if op == TCP_OP_OFFER:
                got.append(arg)
        return RC_SUCCESS, got
    except socket.timeout:
        return _tcp_cancel(got, count)
    except (OSError, ConnectionError):
        return RC_CONNERR, None


def SPI_BurstOut(data: bytes | bytearray) -> int:
    """Send a run of bytes with RPI_READY held high for the whole run.

    This is what makes hardware /WAIT usable.  The CPLD asserts /WAIT only
    while SPI_RDY is high (MSXPi.vhd: wait_assert <= wait_mode and SPI_RDY and
    spi_en and ...), and SPI_ByteTransfer() raises and drops RPI_READY around
    every single byte.  In that inter-byte gap an INIR read on the MSX would
    NOT stall and would silently return a stale byte, desynchronising the
    stream.  Holding RDY up across the burst closes that window.

    Returns RC_SUCCESS, or an error code.  Falls back to per-byte transfers
    only for TCP. GPIO requires a backend that keeps READY asserted.
    """

    if hostType != "RaspberryPi":
        if _tcp_framed:
            rc, _ = tcp_exchange(bytearray(data), TCP_BURST_TIMEOUT)
            return rc
        # raw openMSX link: no RDY line to hold, sendall() is the fast path.
        try:
            conn.sendall(bytes(data))
            return RC_SUCCESS
        except Exception:
            return RC_CONNERR

    if _NATIVE_GPIO is not None:
        try:
            _NATIVE_GPIO.write_burst(bytes(data))
            if _PROFILE:
                _NATIVE_GPIO.report()
            return RC_SUCCESS
        except OSError as exc:
            print(f"Native GPIO burst failed: {exc}")
            return RC_CONNERR

    if not _FAST_GPIO:
        # Per-byte READY gaps are incompatible with the client's INIR loop.
        # Leave READY low so its bounded entry wait fails instead of corrupting
        # the stream. A polled client also gets a transport error, never data.
        return RC_CONNERR

    reg = _GPIO_REG
    SET, CLR, LEV = _GPSET0, _GPCLR0, _GPLEV0
    m_sclk, m_miso, m_cs = _M_SCLK, _M_MISO, _M_CS

    # Bounded, unlike SPI_ByteTransfer's spin.  That one waits forever on
    # purpose - it is the server idling for the next command - but a burst is
    # different: the MSX has committed to reading N bytes, and if it stops
    # early there is nobody left to assert CS.  The driver DOES stop early: on
    # a failed transaction it resynchronises by writing $FF to $56 and
    # abandoning the rest of the reply.  Without a bound the Pi then spins at
    # 100% CPU for ever, which on a single-core Pi starves everything else -
    # including sshd, which drops the session.
    deadline = time.perf_counter() + BURST_CS_TIMEOUT

    reg[SET] = _M_RDY  # up once, for the whole burst
    try:
        for byte_out in bytearray(data):
            spins = 0
            while reg[LEV] & m_cs:  # each byte is still its own
                # CPLD transfer, so CS still cycles
                spins += 1
                # perf_counter() is far too slow to call every iteration, and
                # this loop is the hot path; check it rarely instead.
                if not (spins & 0x3FF) and time.perf_counter() > deadline:
                    return RC_FAILED
            reg[SET] = m_sclk
            reg[CLR] = m_sclk
            for bit in (0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01):
                if byte_out & bit:
                    reg[SET] = m_miso
                else:
                    reg[CLR] = m_miso
                reg[SET] = m_sclk
                reg[CLR] = m_sclk
            reg[SET] = m_sclk
            reg[CLR] = m_sclk
    finally:
        reg[CLR] = _M_RDY  # and down exactly once
    return RC_SUCCESS


def SPI_BurstIn(length: int) -> Tuple[int, Optional[bytearray]]:
    """Receive a run of bytes with RPI_READY held high for the whole run.

    The mirror image of SPI_BurstOut, for the MSX's OTIR side: the CPLD only
    asserts /WAIT while SPI_RDY is high, so the same inter-byte RDY gap that
    would let an INIR read stale data would let an OTIR write vanish.

    Returns (RC_SUCCESS, bytearray) or (error code, None).
    """

    if hostType != "RaspberryPi" and _tcp_framed:
        # passive offers, READY held across the run: exactly SPI_BurstIn's GPIO
        # contract, so an OTIR that starts before them loses bytes here too
        return tcp_exchange(bytes(length), TCP_BURST_TIMEOUT)

    if hostType != "RaspberryPi":
        # raw openMSX link: no RDY line to hold; the burst arrives as an
        # ordinary byte stream.  Read it in one go rather than byte by byte -
        # the MSX sends it as fast as OTIR can run.
        payload = bytearray()
        quickack = getattr(socket, "TCP_QUICKACK", None)
        try:
            conn.settimeout(None if DISABLETIMEOUT else SYNCTRANSFTIMEOUT)
            while len(payload) < length:
                if quickack is not None:
                    try:
                        conn.setsockopt(socket.IPPROTO_TCP, quickack, 1)
                    except OSError:
                        quickack = None
                chunk = conn.recv(length - len(payload))
                if not chunk:
                    return RC_CONNERR, None
                payload.extend(chunk)
        except Exception:
            return RC_CONNERR, None
        return RC_SUCCESS, payload

    # DIAGNOSTIC (not for release): has the MSX already started its OTIR before
    # this burst raised READY?  A write OUT arms a CPLD transfer whether or not
    # READY is up, but /WAIT only holds the Z80 while READY is up - so bytes
    # sent in that window overwrite each other and are lost.  Sampled before
    # anything slow; reported only after the burst, so it adds no latency.
    early = _GPIO_REG is not None and not (_GPIO_REG[_GPLEV0] & _M_CS)

    if _NATIVE_GPIO is not None:
        try:
            data = _NATIVE_GPIO.read_burst(length)
            if early:
                print(
                    "SPI_BurstIn: CS was already low before READY - the MSX started early"
                )
            if _PROFILE:
                _NATIVE_GPIO.report()
            return RC_SUCCESS, data
        except OSError as exc:
            print(f"Native GPIO burst receive failed: {exc}")
            return RC_CONNERR, None

    if not _FAST_GPIO:
        # As in SPI_BurstOut: per-byte READY gaps cannot carry an OTIR burst,
        # so fail the transport instead of accepting corrupted data.
        return RC_CONNERR, None

    reg = _GPIO_REG
    SET, CLR, LEV = _GPSET0, _GPCLR0, _GPLEV0
    m_sclk, m_miso, m_mosi, m_cs = _M_SCLK, _M_MISO, _M_MOSI, _M_CS

    payload = bytearray(length)
    deadline = time.perf_counter() + BURST_CS_TIMEOUT

    reg[SET] = _M_RDY  # up once, for the whole burst
    try:
        reg[CLR] = m_miso  # passive receive drives MISO low
        for i in range(length):
            spins = 0
            while reg[LEV] & m_cs:
                spins += 1
                if not (spins & 0x3FF) and time.perf_counter() > deadline:
                    return RC_FAILED, None
            reg[SET] = m_sclk  # leading tick
            reg[CLR] = m_sclk
            byte_in = 0
            for bit in (0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01):
                reg[SET] = m_sclk
                if reg[LEV] & m_mosi:
                    byte_in |= bit
                reg[CLR] = m_sclk
            reg[SET] = m_sclk  # trailing tick
            reg[CLR] = m_sclk
            payload[i] = byte_in
    finally:
        reg[CLR] = _M_RDY  # and down exactly once
    return RC_SUCCESS, payload


def tick_sclk():

    if _FAST_GPIO:
        _GPIO_REG[_GPSET0] = _M_SCLK
        _GPIO_REG[_GPCLR0] = _M_SCLK
        return
    GPIO.output(SPI_SCLK, GPIO.HIGH)
    GPIO.output(SPI_SCLK, GPIO.LOW)


def SPI_ByteTransfer(byte_out: Optional[int] = None) -> Tuple[int, Optional[int]]:

    byte_in = 0
    if hostType == "RaspberryPi":
        # GPIO-based SPI emulation

        if _FAST_GPIO:
            return _spi_byte_fast(byte_out)

        GPIO.output(RPI_READY, GPIO.HIGH)
        while GPIO.input(SPI_CS):
            pass

        tick_sclk()
        for bit in [0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01]:
            # Send bit if byte_out is provided
            if byte_out is not None:
                GPIO.output(SPI_MISO, GPIO.HIGH if (byte_out & bit) else GPIO.LOW)
            else:
                GPIO.output(SPI_MISO, GPIO.LOW)  # Passive receive mode

            GPIO.output(SPI_SCLK, GPIO.HIGH)

            # Always read MOSI
            if GPIO.input(SPI_MOSI):
                byte_in |= bit

            GPIO.output(SPI_SCLK, GPIO.LOW)

        tick_sclk()
        GPIO.output(RPI_READY, GPIO.LOW)
    elif _tcp_framed:
        # one offer, READY dropped after it - the per-byte GPIO contract
        rc, got = tcp_exchange(
            (0 if byte_out is None else byte_out,),
            None if DISABLETIMEOUT else SYNCTRANSFTIMEOUT,
        )
        if rc != RC_SUCCESS:
            print(f"SPI_ByteTransfer(): virtual SPI transfer failed rc={rc:#04x}")
            return rc, None
        byte_in = got[0]
    else:
        if _tcp_rx:
            # MSX data an old openMSX sent before the hello timed out
            if byte_out is None:
                return RC_SUCCESS, _tcp_rx.pop(0)
        if DISABLETIMEOUT == True:
            conn.settimeout(None)
        else:
            conn.settimeout(SYNCTRANSFTIMEOUT)
        if byte_out is not None:
            conn.sendall(bytes([byte_out]))
        else:
            try:
                buf = conn.recv(1)
                if buf == b"":  # connection closed
                    print("SPI_ByteTransfer(): connection closed by peer")
                    return RC_CONNERR, None
                byte_in = buf[0]
            except socket.timeout:
                print("SPI_ByteTransfer(): recv timed out")
                return RC_FAILED, None
            except IndexError:
                print("SPI_ByteTransfer(): e-connection closed by peer")
                return RC_CONNERR, None

    return RC_SUCCESS, byte_in


def SPI_ReadPayload(length: int) -> Tuple[int, Optional[bytearray]]:
    """Exactly length bytes; header, checksum and status remain at the caller."""
    if hostType == "RaspberryPi" and _NATIVE_GPIO is not None:
        try:
            data = _NATIVE_GPIO.read(length)
            if _PROFILE:
                _NATIVE_GPIO.report()
            return RC_SUCCESS, data
        except OSError as e:
            print(f"SPI_ReadPayload: {e}")
            return RC_CONNERR, None
    if hostType != "RaspberryPi" and _tcp_framed:
        return tcp_exchange(bytes(length), SYNCTRANSFTIMEOUT, hold=False)
    payload = bytearray(length)
    quickack = (
        getattr(socket, "TCP_QUICKACK", None) if hostType != "RaspberryPi" else None
    )
    for i in range(length):
        # Linux clears TCP_QUICKACK by itself after a few packets, and a burst
        # write arrives as hundreds of one-byte packets, so re-arm it while
        # draining (see the accept() above). No-op on the Pi's GPIO link.
        if quickack is not None and conn is not None and not i % 32:
            try:
                conn.setsockopt(socket.IPPROTO_TCP, quickack, 1)
            except OSError:
                quickack = None
        rc, byte = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return rc, None
        payload[i] = byte
    return RC_SUCCESS, payload


def SPI_WritePayload(payload: bytes | bytearray) -> int:
    """Same per-byte READY/CS contract as SPI_ByteTransfer, in native chunks."""
    if hostType == "RaspberryPi" and _NATIVE_GPIO is not None:
        try:
            _NATIVE_GPIO.write(payload)
            if _PROFILE:
                _NATIVE_GPIO.report()
            return RC_SUCCESS
        except OSError as e:
            print(f"SPI_WritePayload: {e}")
            return RC_CONNERR
    if hostType != "RaspberryPi" and _tcp_framed:
        rc, _ = tcp_exchange(bytes(payload), SYNCTRANSFTIMEOUT, hold=False)
        return rc
    for byte in payload:
        rc, _ = SPI_ByteTransfer(byte if isinstance(byte, int) else ord(byte))
        if rc != RC_SUCCESS:
            return rc
    return RC_SUCCESS


_stopping = False


def _system_stopping():
    """True once the Pi is shutting down or rebooting.  A server started then
    (msxpi-monitor restarting it) must not announce itself online: it is about
    to be SIGKILLed and could never take the LED down again.  It costs a
    subprocess, so it runs once, when the link is set up; the per-block and
    per-command announces only read the resulting flag."""
    global _stopping
    if not _stopping:
        try:
            state = subprocess.run(
                ["systemctl", "is-system-running"],
                capture_output=True,
                text=True,
                timeout=1,
            ).stdout.strip()
            _stopping = state == "stopping"
        except Exception:
            pass
    return _stopping


def cpld_announce(online):
    """Tell the CPLD the server is online (True) or going offline (False).

    One SCLK rising edge while no transfer is running, with MISO carrying the
    state.  Only the v0.8.2-board CPLD build uses it - to light its LED while
    the server is up - and every other CPLD firmware, old or new, ignores an
    SCLK edge outside a transfer (checked in tb_MSXPi.vhd against v1.3).

    Never sent with CS low: then the MSX has a byte pending and this edge
    would be taken as that byte's first clock.  Best effort - a failure here
    must never stop the server."""
    if hostType != "RaspberryPi":
        return
    if online and _stopping:  # set by _system_stopping(), see there
        return
    try:
        if GPIO.input(SPI_CS) == GPIO.LOW:
            if online:
                return
            # Going offline with a byte pending: clock it out first (ten
            # edges, as SPI_ByteTransfer does) - the flag only changes
            # outside a transfer.  Nobody reads that byte any more.
            for _ in range(10):
                GPIO.output(SPI_SCLK, GPIO.HIGH)
                GPIO.output(SPI_SCLK, GPIO.LOW)
        GPIO.output(SPI_MISO, GPIO.HIGH if online else GPIO.LOW)
        GPIO.output(SPI_SCLK, GPIO.HIGH)
        GPIO.output(SPI_SCLK, GPIO.LOW)
    except Exception:
        pass


def release_gpio():
    """Clean exit: tell the CPLD we are going offline, then release the pins -
    except SCLK and MISO, which stay driven low.

    Released, those two float into the CPLD, and a noise edge on SCLK with
    MISO floating high reads as an "online" announce: the v0.8.2 LED came
    back on after the server had stopped.  A halted Pi keeps its outputs as
    they are, so the lines stay quiet until power-off.  RPI_READY is still
    released as before - the /WAIT safety story relies on its pull-down."""
    global _stopping
    _stopping = True  # nothing may relight the LED from here on
    print("MSXPi Server: announcing offline to the CPLD")
    cpld_announce(False)
    try:
        GPIO.output(SPI_SCLK, GPIO.LOW)
        GPIO.output(SPI_MISO, GPIO.LOW)
        pins = [SPI_CS, SPI_MOSI, RPI_READY]
        if RPI_SHUTDOWN is not None:
            pins.append(RPI_SHUTDOWN)
        GPIO.cleanup(pins)
    except Exception:
        GPIO.cleanup()


def initialize_connection(
    host: str, port: int, on_button: Callable
) -> Optional[socket.socket]:
    if hostType == "RaspberryPi":
        init_spi_bitbang()
        # Before READY goes up, so the MSX cannot start a byte under it.
        if _system_stopping():
            print("MSXPi Server: system is stopping - not announcing online")
        cpld_announce(True)
        GPIO.output(RPI_READY, GPIO.HIGH)
        time.sleep(0.2)
        GPIO.output(RPI_READY, GPIO.LOW)

        # Idempotent on purpose: this function is the error-recovery path for
        # the command loop below, so it runs again on every glitch.  A second
        # add_event_detect on the same channel raises "Conflicting edge
        # detection already enabled", which used to escape and kill the
        # server - turning one bad byte into a crash loop that the monitor
        # restarted for ever, with the MSX unable to boot at all.
        if RPI_SHUTDOWN is None:
            print("MSXPi Server: no shutdown button (RPI_SHUTDOWN=none in msxpi.ini)")
        else:
            try:
                GPIO.remove_event_detect(RPI_SHUTDOWN)
            except Exception:
                pass
            try:
                GPIO.add_event_detect(
                    RPI_SHUTDOWN, GPIO.FALLING, callback=on_button, bouncetime=200
                )
                print(
                    f"MSXPi Server: shutdown button on GPIO {RPI_SHUTDOWN} "
                    f"(press: reboot, hold 3 s: shutdown)"
                )
            except Exception as e:
                # Losing the shutdown button is a far smaller problem than
                # losing the server, so carry on rather than raise.
                print(f"MSXPi Server: shutdown button unavailable ({e})")
        logger.info(f"[MSXPi Server on {hostType}] Listening on GPIOs:")
        logger.info(
            f" ** CS={SPI_CS}, CLK={SPI_SCLK}, MOSI={SPI_MOSI}, MISO={SPI_MISO}, PI_READY={RPI_READY} **"
        )
        return None
    else:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((host, port))
        s.listen(1)
        logger.info(f"[MSXPi Server on {hostType}] Listening on {host}:{port}...")
        return s
