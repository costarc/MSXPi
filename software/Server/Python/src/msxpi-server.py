#!/usr/bin/python3
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
# External module imports

from fileinput import filename
from tarfile import BLOCKSIZE
import time
import subprocess
import struct
from urllib.request import urlopen
from urllib.parse import unquote
import requests
import mmap
# import fcntl # does not work in Windows
import os
import sys
import platform
from os.path import exists
from subprocess import Popen,PIPE,STDOUT
from html.parser import HTMLParser
import datetime
import time
import glob
import array
import socket
import errno
import select
import base64
import math
import re
from random import randint
from fs import open_fs
import threading
from io import StringIO
from contextlib import redirect_stdout
import shutil


version = "1.6"
BuildId = "20260916.057"

CMDSIZE = 9
MSGSIZE = 128
BLKSIZE = 512
SECTORSIZE = 512
BULKBLKSIZE = 3 + 4096
MAXBUFSIZE = 48*1024       # 48 KB buffer in the MSX side

SPI_SCLK_LOW_TIME = 0.001
SPI_SCLK_HIGH_TIME = 0.001

GLOBALRETRIES       = 10
MAX_BLOCK_RETRIES   = 3
SPI_INT_TIME        = 3000
PIWAITTIMEOUTOTHER  = 120     # seconds
PIWAITTIMEOUTBIOS   = 60      # seconds
SYNCTIMEOUT         = 30
# 180, not 30: the MSX drains a block at a few hundred bytes a second, so an
# 8 KB block can sit for the best part of a minute before the far end answers.
# At 30 the server gave up mid-transfer and reported a checksum failure that
# was really just impatience.
BYTETRANSFTIMEOUT   = 180
SYNCTRANSFTIMEOUT   = 180
HTTP_TIMEOUT        = 15     # seconds for any web fetch; an unreachable host must not hang a command
DISABLETIMEOUT      = False
READY_ACK           = 0xA0
SENDNEXT            = 0xA1
ENDTRANSFER         = 0xA2
READY               = 0xAA
RC_CHKSUM_ERR       = 0xAD
WAIT                = 0xAE

RC_SUCCESS          =    0xE0
RC_INVALIDCOMMAND   =    0xE1
RC_ESCPRESSED       =    0xE2
RC_BUFOVFLW         =    0xE3
RC_INVALIDDATASIZE  =    0xE4
RC_HANDSHAKEERR     =    0xE5
RC_FILENOTFOUND     =    0xE6
RC_FAILED           =    0xE7
RC_CONNERR          =    0xE8
RC_WAIT             =    0xE9
RC_READY            =    0xEA
RC_SUCCNOSTD        =    0xEB
RC_FAILNOSTD        =    0xEC
RC_TERMINATE        =    0xED
RC_UNEXPECTEDDATA   =    0xEE
RC_UNDEFINED        =    0xEF

# ROM header sent to the MSX immediately before a ROM image, so the client
# knows how to load it (plain linear copy vs. mapper-aware loading).
ROM_HEADER_MAGIC    =    0x52   # 'R'
ROM_HEADER_VERSION  =    1
ROM_HEADER_SIZE     =    16
MAPPER_PLAIN        =    0      # linear ROM, loaded exactly as today
MAPPER_KONAMI       =    1      # 8K banks
MAPPER_ASCII8       =    2      # 8K banks
MAPPER_ASCII16      =    3      # 16K banks
MAPPER_REJECTED     =    0xFF   # selection rejected; reason string follows the header, no ROM body
PLAIN_ROM_MAX_SIZE  =    32768  # client's fixed load window for MAPPER_PLAIN
ROM_MAX_SIZE         =    1048576  # sanity cap for mapped ROMs (1MB covers all commercial Konami/ASCII8/ASCII16 megaROMs)

# Force stdout to flush on every newline automatically
sys.stdout.reconfigure(line_buffering=True)

# Import IRC client wrappers (module-level functions prefixed with "irc_")
# Guarded import so server still runs even if irc_client is absent or raises at import.
''''try:
    from irc_client import *  # brings irc_connect, irc_read_unread, etc. into globals()
    print("IRC client integrated: irc_* commands available")
except Exception as _e:
    print(f"Warning: failed to import irc_client module: {_e}")
    '''
# ---------------------------------------------------------------------------
# Ethernet UNAPI shuttle (msxpi_eth.py).
#
# Guarded like the IRC import: the server must still run if the module is
# missing.  eth_handle_opcode() is called from recvdata2()'s wait-for-READY
# loop, i.e. from the byte that loop was about to discard, so it must be cheap
# and must report False for anything that is not one of its opcodes.
#
# The shuttle is built lazily on the first opcode rather than at import: the
# transport functions it closes over (SPI_ByteTransfer / SPI_BurstOut) are
# defined further down this file, and on a Pi the GPIO setup has not run yet at
# import time.
# ---------------------------------------------------------------------------
try:
    import msxpi_eth as _eth_mod
except Exception as _e:
    _eth_mod = None
    print(f"Warning: failed to import msxpi_eth module: {_e}")

_eth_shuttle = None


# Module-level rather than lambdas built per shuttle: one less Python frame on
# every reply. The shuttle's contract is 0 = success (see msxpi_eth.EthShuttle);
# RC_SUCCESS is 0xE0 - truthy - so it must be mapped, not passed through, or
# every write would look like a failure.
def _eth_write_byte(v):
    return 0 if SPI_ByteTransfer(v)[0] == RC_SUCCESS else 1


def _eth_write_burst(data):
    return 0 if SPI_BurstOut(data) == RC_SUCCESS else 1


def eth_get_shuttle():
    """The EthShuttle, created on first use.  None if the module is absent."""
    global _eth_shuttle
    if _eth_mod is None:
        return None
    if _eth_shuttle is None:
        link = _eth_mod.make_link(log=print)
        _eth_shuttle = _eth_mod.EthShuttle(
            link,
            read_byte=SPI_ByteTransfer,
            # The shuttle's contract is 0 = success (see msxpi_eth.EthShuttle).
            # It deliberately does not know about this file's RC_* values, and
            # RC_SUCCESS is 0xE0 - truthy - so it must be mapped, not passed
            # through, or every write would look like a failure.
            write_byte=_eth_write_byte,
            write_burst=_eth_write_burst,
            log=print)
        print("eth: Ethernet UNAPI shuttle ready (%s)"
              % type(link).__name__)
        _eth_note_link(link)
    return _eth_shuttle


# Seconds between attempts to replace a MockLink with the real TAP.
ETH_TAP_RETRY = 5.0
_eth_link_is_mock = False   # checked on the opcode path, so keep it a bool
_eth_tap_retry_at = 0.0


def _eth_note_link(link):
    """Remember whether the shuttle ended up on MockLink."""
    global _eth_link_is_mock
    _eth_link_is_mock = (_eth_mod is not None
                         and isinstance(link, _eth_mod.MockLink))


def _eth_retry_tap():
    """Swap a MockLink for the real TAP once msxpi0 becomes openable.

    make_link() runs once, lazily, on the first Ethernet opcode, and its result
    used to be kept for the life of the process.  msxpi-monitor starts
    msxpi-tcpip-setup.sh in the BACKGROUND and the server immediately after, so
    whether msxpi0 exists and is owned by the server's user when that first
    opcode lands is a race.  Losing it pinned MockLink, which answers every
    opcode correctly and carries no traffic whatsoever - the MSX installs INL,
    reports the link up, and nothing reaches the network - until somebody
    restarted the server by hand.

    The MSX-visible MAC is the same fixed address on every link (BaseLink's
    default), so a swap is invisible to the stack on the other side; the two
    pieces of state the MSX can change, ETH_ENABLE and ETH_FILTERS, are carried
    across.  Retries are silent: on a host that will never have a TAP (the
    openMSX harness) this runs for the life of the process.
    """
    global _eth_tap_retry_at
    now = time.monotonic()
    if now < _eth_tap_retry_at:
        return
    _eth_tap_retry_at = now + ETH_TAP_RETRY
    try:
        # TapLink directly, not make_link: its fallback would build a throwaway
        # MockLink (threads and all) and log a line on every failed retry.
        link = _eth_mod.TapLink()
    except Exception:
        return
    old = _eth_shuttle.link
    link.enabled = old.enabled
    link.filters = old.filters
    _eth_shuttle.link = link
    old.close()
    _eth_note_link(link)
    print("eth: msxpi0 is up now - MockLink replaced by the TAP", flush=True)


# Hoisted out of eth_handle_opcode: the membership test below runs on EVERY
# byte recvdata2() reads while waiting for READY, so it is on the path for all
# traffic and not just for opcodes. A module-global frozenset lookup avoids an
# attribute lookup on _eth_mod each time.
_eth_opcodes = _eth_mod.OPCODES if _eth_mod is not None else frozenset()
_eth_handle = None      # the shuttle's bound handle(), cached on first use


def eth_handle_opcode(opcode):
    """True if `opcode` was an Ethernet UNAPI op and has been served."""
    if opcode not in _eth_opcodes:
        return False
    global _eth_handle
    if _eth_handle is None:
        shuttle = eth_get_shuttle()
        if shuttle is None:
            return False
        # Cache the bound method: saves a function call plus an attribute
        # lookup per opcode, on a path where the per-transaction fixed cost is
        # what dominates short transactions.
        _eth_handle = shuttle.handle
    if _eth_link_is_mock:
        # Degraded: look for the TAP again (rate limited inside). Only ever on
        # this path while the link is Mock, so it costs a bool test otherwise.
        _eth_retry_tap()
    try:
        return _eth_handle(opcode)
    except Exception as e:
        print(f"eth: error serving opcode {hex(opcode)}: {e}")
        return True   # consumed; do not fall through to the garbage branch

def build_rom_header(mapper_type, bank_size_kb, bank_count, total_size):
    """Pack the fixed 16-byte ROM header: magic, protocol version, mapper
    type, bank size (KB), bank count, and total ROM size in bytes.
    mapper_type MAPPER_PLAIN keeps today's client behavior unchanged;
    the other values are reserved for mapper-aware loading (not yet
    implemented client-side)."""
    # Konami SCC only differs in where the cartridge decodes its bank writes,
    # which the server has already patched; on the MSX it loads exactly like
    # Konami, and the clients only know types 1-3.
    if mapper_type == MAPPER_KONAMI_SCC:
        mapper_type = MAPPER_KONAMI
    return struct.pack("<BBBBHI6x", ROM_HEADER_MAGIC, ROM_HEADER_VERSION,
                        mapper_type, bank_size_kb, bank_count, total_size)

# Bank-select write addresses (as LD (nn),A / 0x32 lo hi) each mapper type
# responds to. ASCII8 and ASCII16 both use 0x6000/0x7000, so those two
# addresses alone don't distinguish them - 0x6800/0x7800 are ASCII8-only,
# 0x8000/0xA000 are Konami-only, and 0x5000/0x9000/0xB000 are Konami SCC
# only (SCC also uses 0x7000, which overlaps ASCII8/16). Konami SCC is
# reported as plain MAPPER_KONAMI (same 8K banks, same LD (nn),A bank-select
# mechanism the wire protocol/transfer cares about - the SCC sound chip's
# own registers don't affect bank-switch addresses or chunking at all).
# The client (EXECROM's /W option) detects SCC-ness itself from the ROM's
# own content via its existing disk-load signature table (checkon/konatab -
# the same lookup a disk-sourced Konami SCC load already used), so nothing
# server-side needs to flag it specially.
# This is a heuristic (opcode-pattern scan, not a hash database), so it
# can misidentify unusual/hand-rolled ROMs - good enough for the common
# commercial mapper layouts.
from mapper_detect import (detect_mapper as _detect_mapper_v2,
                            patch_bank_switches, patch_indexed_switches,
                            PATCH_WINDOWS,
                            neutralise_rom_writes, neutralise_scc_writes,
                            MAPPER_KONAMI_SCC,
                            load_romdb, romdb_lookup)

# Handler addresses the MSX will have relocated its resident bank-switch code
# to. The client sends its own with the selection so the two sides cannot
# drift; these are only the fallback for an older client that sends none, in
# which case the MSX patches the image itself as it used to.
DEFAULT_HANDLERS = (0xF9C0, 0xFA00, 0xFA40, 0xFA80, 0xFAC0, 0xFB00)


def handlers_for(mapper_type, h):
    """Pick the handler list for this mapper, in PATCH_WINDOWS order.
    h is (win1, win2, win3, win4, page1, page2)."""
    if mapper_type == MAPPER_ASCII8:   return [h[0], h[1], h[2], h[3]]
    if mapper_type == MAPPER_ASCII16:  return [h[4], h[5]]
    if mapper_type == MAPPER_KONAMI:   return [h[1], h[2], h[3]]  # 6000/8000/A000 ranges
    if mapper_type == MAPPER_KONAMI_SCC:
        return [h[0], h[1], h[2], h[3]]                            # 5000/7000/9000/B000
    return None


def patch_for_msx(buf, mapper_type, handlers):
    """Convert the ROM's bank-switch writes into CALLs to the MSX-side
    handlers, so the MSX only has to store blocks and run. Scanning a 128KB ROM
    on a 3.58MHz Z80 cost 16KB per storage segment before the game started."""
    if not handlers or mapper_type not in PATCH_WINDOWS:
        return buf, 0
    hs = handlers_for(mapper_type, handlers)
    if not hs:
        return buf, 0
    buf, n = patch_bank_switches(buf, mapper_type, hs)
    if mapper_type == MAPPER_KONAMI_SCC:
        buf, m = neutralise_scc_writes(buf)
        if m:
            print(f"neutralised {m} SCC sound-register writes")
        n += m
    # A seventh address is the MSX's window dispatcher, for games that compute
    # the register instead of storing to it directly (HYDLIDE3.ROM).
    if len(handlers) >= 7:
        buf, m = patch_indexed_switches(buf, mapper_type, handlers[6])
        if m:
            print(f"patched {m} computed window selects")
        n += m
    return buf, n


KONAMI_SCC_UNIQUE_ADDRS = (0x5000, 0x9000, 0xB000)
KONAMI_UNIQUE_ADDRS     = (0x8000, 0xA000)
ASCII8_UNIQUE_ADDRS     = (0x6800, 0x7800)
ASCII16_ADDRS           = (0x6000, 0x7000)

def detect_mapper(rom_bytes):
    """Scan rom_bytes for bank-select write patterns and guess the mapper
    type. Returns (mapper_type, bank_size_kb) or (None, None) if nothing
    recognizable/supported was found (caller should treat the ROM as
    unsupported)."""
    write_addrs = set()
    for i in range(len(rom_bytes) - 2):
        if rom_bytes[i] == 0x32:  # LD (nn),A
            write_addrs.add(rom_bytes[i + 1] | (rom_bytes[i + 2] << 8))

    # Delegated to mapper_detect: same exact-address chain as before, plus a
    # repetition-based fallback for ROMs it rejects outright (BUBBLE.ROM and
    # ISHTAR.ROM bank at 6FF8h/77F8h/7FF8h and 67FFh/77FFh respectively, so
    # they never matched the exact addresses). See MEGAROM_MAPPER_NOTES.md.
    del write_addrs
    return _detect_mapper_v2(rom_bytes)

st_init             =    0       # waiting loop, waiting for a command
st_cmd              =    1       # transfering data for a command
st_recvdata         =    2
st_senddata         =    4
st_synch            =    5       # running a command received from MSX
st_runcmd           =    6
st_shutdown         =    99

NoTimeOutCheck      = False
TimeOutCheck        = True

MSXPIHOME = "/home/pi/msxpi"
RAMDISK = "/media/ramdisk"
TMPFILE = RAMDISK + "/msxpi.tmp"

# irc
channel = "#msxpi"
allchann = []
ircsock = None
errcount = 0
msxdos1boot = False

HOST = '0.0.0.0'  # Listen on all interfaces
PORT = 5000       # Match this with serverPort in your C++ code
conn = None

hostType = "RaspberryPi"
RPI_SHUTDOWN = 26
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
            if "Raspberry Pi" in cpuinfo or "BCM" in cpuinfo or "Raspberry" in platform.uname().node:
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
_GPSET0 = 0x1C >> 2      # write 1 to set   a pin high
_GPCLR0 = 0x28 >> 2      # write 1 to clear a pin low
_GPLEV0 = 0x34 >> 2      # read pin levels

_FAST_GPIO = False
_GPIO_REG  = None
_NATIVE_GPIO = None

# ---------------------------------------------------------------------------
# Profiler.  Enable with MSXPI_PROFILE=1.  Answers one question: how much of the
# wall-clock time is actually spent inside SPI_ByteTransfer()?
#
# 8 KB in 9.6 s is ~1.17 ms/byte, but SPI_ByteTransfer() should be nowhere near
# that.  If "in transfer" comes back as a small fraction of elapsed, the cost is
# in the protocol/Python layers above, or in waiting for the MSX - and no amount
# of GPIO tuning will touch it.
_PROFILE   = bool(os.environ.get("MSXPI_PROFILE"))
_prof_n    = 0        # transfers completed
_prof_busy = 0.0      # seconds inside SPI_ByteTransfer, total
_prof_spin = 0.0      # of which: spinning on SPI_CS, i.e. waiting for the MSX
_prof_t0   = None     # wall clock at the first transfer
_PROF_EVERY = 1024


def _prof_report(force=False):
    global _prof_n, _prof_busy, _prof_spin, _prof_t0
    if not _prof_n:
        return
    if not force and (_prof_n % _PROF_EVERY):
        return
    elapsed = time.perf_counter() - _prof_t0
    per = _prof_busy / _prof_n * 1e6
    spin = _prof_spin / _prof_n * 1e6
    print(f"[prof] {_prof_n} bytes | wall {elapsed:.2f}s "
          f"({elapsed / _prof_n * 1e6:.0f} us/byte) | "
          f"in SPI_ByteTransfer {_prof_busy:.2f}s ({per:.0f} us/byte, "
          f"{100.0 * _prof_busy / elapsed:.1f}% of wall) | "
          f"of which spinning on CS {spin:.0f} us/byte | "
          f"unaccounted {100.0 * (elapsed - _prof_busy) / elapsed:.1f}%")
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
        print("init_fast_gpio(): MSXPI_SLOW_GPIO set - using the original RPi.GPIO path")
        return

    pins = (SPI_SCLK, SPI_MISO, SPI_MOSI, SPI_CS, RPI_READY)
    if any(p is None or p < 0 or p > 31 for p in pins):
        print(f"init_fast_gpio(): pin(s) outside GPIO0-31 {pins} - staying on RPi.GPIO")
        return

    try:
        import ctypes
        fd = os.open("/dev/gpiomem", os.O_RDWR | os.O_SYNC)
        try:
            mm = mmap.mmap(fd, 4096, mmap.MAP_SHARED,
                           mmap.PROT_READ | mmap.PROT_WRITE, offset=0)
        finally:
            os.close(fd)
        reg = (ctypes.c_uint32 * 1024).from_buffer(mm)

        m_rdy = 1 << RPI_READY

        # Self-test: drive RPI_READY through the register window and read it back
        # through RPi.GPIO.  If the offsets or the SoC are wrong this fails here
        # rather than silently corrupting every transfer.
        reg[_GPSET0] = m_rdy
        hi_ok = (GPIO.input(RPI_READY) == 1)
        reg[_GPCLR0] = m_rdy
        lo_ok = (GPIO.input(RPI_READY) == 0)
        if not (hi_ok and lo_ok):
            raise RuntimeError(f"register self-test failed (high={hi_ok} low={lo_ok})")

        _GPIO_REG = reg
        _M_SCLK = 1 << SPI_SCLK
        _M_MISO = 1 << SPI_MISO
        _M_MOSI = 1 << SPI_MOSI
        _M_CS   = 1 << SPI_CS
        _M_RDY  = m_rdy
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
            missing = [m for m in ('read', 'write', 'read_burst', 'write_burst')
                       if not callable(getattr(native, m, None))]
            if missing:
                raise AttributeError(f"msxpi_gpio_native.py is out of date, no {', '.join(missing)} "
                                     f"- run update.sh")
            _NATIVE_GPIO = native
            print(f"init_fast_gpio(): native GPIO payload engine active "
                  f"(half-period {_NATIVE_GPIO.half_period_ns} ns)")
        except (OSError, ValueError, ImportError, AttributeError) as e:
            print(f"init_fast_gpio(): native engine unavailable ({e}); using Python GPIO")


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

    reg[SET] = _M_RDY                       # RPI_READY high
    while reg[LEV] & _M_CS:                 # spin until the CPLD asserts CS
        pass

    if _PROFILE:
        _t_spun = time.perf_counter()

    reg[SET] = m_sclk                       # leading tick
    reg[CLR] = m_sclk

    for bit in (0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01):
        if byte_out is not None and (byte_out & bit):
            reg[SET] = m_miso
        else:
            reg[CLR] = m_miso               # passive receive drives MISO low
        reg[SET] = m_sclk
        if reg[LEV] & m_mosi:
            byte_in |= bit
        reg[CLR] = m_sclk

    reg[SET] = m_sclk                       # trailing tick
    reg[CLR] = m_sclk
    reg[CLR] = _M_RDY                       # RPI_READY low

    if _PROFILE:
        _t_done = time.perf_counter()
        _prof_n += 1
        _prof_busy += _t_done - _t_enter
        _prof_spin += _t_spun - _t_enter
        _prof_report()

    return RC_SUCCESS, byte_in


# Block-size / length bit that marks a /WAIT burst payload (see sendmultiblock).
BURST_FLAG = 0x8000


def burst_capable():
    """True when SPI_BurstOut can hold READY for a whole block (or no READY: TCP)."""
    return hostType != "RaspberryPi" or _NATIVE_GPIO is not None or _FAST_GPIO


# How long to wait for the MSX to collect a burst before giving up on it.
# Generous next to a per-byte time of tens of microseconds, but short enough
# that an abandoned burst cannot wedge the server.
BURST_CS_TIMEOUT = 0.25     # seconds


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
TCP_HELLO_TIMEOUT = 1.0     # seconds for openMSX to answer the hello
TCP_BURST_TIMEOUT = 10.0    # emulation can run slower than real time
_tcp_framed = False
_tcp_rx = bytearray()       # received but not yet consumed


def tcp_handshake(c):
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
        return RC_SUCCESS, got      # the last one landed while cancelling
    return RC_FAILED, None


def tcp_exchange(misos, timeout, hold=True):
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


def SPI_BurstOut(data):
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
    global conn, hostType

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

    reg[SET] = _M_RDY                       # up once, for the whole burst
    try:
        for byte_out in bytearray(data):
            spins = 0
            while reg[LEV] & m_cs:          # each byte is still its own
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
        reg[CLR] = _M_RDY                   # and down exactly once
    return RC_SUCCESS


def SPI_BurstIn(length):
    """Receive a run of bytes with RPI_READY held high for the whole run.

    The mirror image of SPI_BurstOut, for the MSX's OTIR side: the CPLD only
    asserts /WAIT while SPI_RDY is high, so the same inter-byte RDY gap that
    would let an INIR read stale data would let an OTIR write vanish.

    Returns (RC_SUCCESS, bytearray) or (error code, None).
    """
    global conn, hostType

    if hostType != "RaspberryPi" and _tcp_framed:
        # passive offers, READY held across the run: exactly SPI_BurstIn's GPIO
        # contract, so an OTIR that starts before them loses bytes here too
        return tcp_exchange(bytes(length), TCP_BURST_TIMEOUT)

    if hostType != "RaspberryPi":
        # raw openMSX link: no RDY line to hold; the burst arrives as an
        # ordinary byte stream.  Read it in one go rather than byte by byte -
        # the MSX sends it as fast as OTIR can run.
        payload = bytearray()
        quickack = getattr(socket, 'TCP_QUICKACK', None)
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
                print("SPI_BurstIn: CS was already low before READY - the MSX started early")
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

    reg[SET] = _M_RDY                       # up once, for the whole burst
    try:
        reg[CLR] = m_miso                   # passive receive drives MISO low
        for i in range(length):
            spins = 0
            while reg[LEV] & m_cs:
                spins += 1
                if not (spins & 0x3FF) and time.perf_counter() > deadline:
                    return RC_FAILED, None
            reg[SET] = m_sclk               # leading tick
            reg[CLR] = m_sclk
            byte_in = 0
            for bit in (0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01):
                reg[SET] = m_sclk
                if reg[LEV] & m_mosi:
                    byte_in |= bit
                reg[CLR] = m_sclk
            reg[SET] = m_sclk               # trailing tick
            reg[CLR] = m_sclk
            payload[i] = byte_in
    finally:
        reg[CLR] = _M_RDY                   # and down exactly once
    return RC_SUCCESS, payload


def tick_sclk():

    global SPI_SCLK
    if _FAST_GPIO:
        _GPIO_REG[_GPSET0] = _M_SCLK
        _GPIO_REG[_GPCLR0] = _M_SCLK
        return
    GPIO.output(SPI_SCLK, GPIO.HIGH)
    GPIO.output(SPI_SCLK, GPIO.LOW)

def SPI_ByteTransfer(byte_out=None):
    
    global conn, hostType
    byte_in = 0    
    if hostType == "RaspberryPi":
        # GPIO-based SPI emulation
        global SPI_CS, RPI_READY

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
        rc, got = tcp_exchange((0 if byte_out is None else byte_out,),
                               None if DISABLETIMEOUT else SYNCTRANSFTIMEOUT)
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
            #print("disabling timeout")
            conn.settimeout(None)
        else:
            #print("enabling timeout")
            conn.settimeout(SYNCTRANSFTIMEOUT)
        if byte_out is not None:
            # print("SPI_ByteTransfer(): Non-Raspberry Pi conn.sendall")
            conn.sendall(bytes([byte_out]))
            #print(f"Sent: {chr(byte_out)}")
            #print(f"Sent: {chr(byte_out)}")
        else:
            # print("SPI_ByteTransfer(): Non-Raspberry Pi conn.recv")
            try:
                #byte_in = conn.recv(1)[0]  # Passive receive mode
                buf = conn.recv(1)
                if buf == b'':   # connection closed
                    print("SPI_ByteTransfer(): connection closed by peer")
                    return RC_CONNERR, None
                byte_in = buf[0]
            except socket.timeout:
                print("SPI_ByteTransfer(): recv timed out")
                return RC_FAILED,None
            except IndexError:
                print("SPI_ByteTransfer(): e-connection closed by peer")
                return RC_CONNERR, None

    
            #print(f"Received: {chr(byte_in)}")
    return RC_SUCCESS,byte_in
    

def SPI_ReadPayload(length):
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
    quickack = getattr(socket, 'TCP_QUICKACK', None) if hostType != "RaspberryPi" else None
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


def SPI_WritePayload(payload):
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

# create a subclass and override the handler methods
class MyHTMLParser(HTMLParser):
    def __init__(self):
        self.reset()
        self.NEWTAGS = []
        self.NEWATTRS = []
        self.HTMLDATA = []
    def handle_starttag(self, tag, attrs):
        self.NEWTAGS.append(tag)
        self.NEWATTRS.append(attrs)
    def handle_data(self, data):
        self.HTMLDATA.append(data)
    def clean(self):
        self.NEWTAGS = []
        self.NEWATTRS = []
        self.HTMLDATA = []
    def convert_charrefs(self, data):
        print("MyHTMLParser: convert_charrefs found :", data)
                
def pathExpander(path, basepath = ''):
    #print(f"pathExpander()")
    
    path=path.strip().rstrip(' \t\n\0')
    
    if path.strip() == "..":
        path = basepath.rsplit('/', 1)[0]
        basepath = ''
    if len(path) == 0 or path == '' or path.strip() == "." or path.strip() == "*":
        path = basepath
        basepath = ''
    if path.startswith('/'):
        urltype = 0 # this is an absolute local path
        newpath = path
    elif (path.lower().startswith('m:')):
        urltype = 1 # this is a network path
        newpath = getMSXPiVar('DriveM') + '/' + path.split(':')[1]
    elif (path.lower().startswith('r1:')):
        urltype = 1 # this is a network path
        newpath = getMSXPiVar('DriveR1') + '/' + path.split(':')[1]
    elif (path.lower().startswith('r2:')):
        urltype = 1 # this is a network path
        newpath = getMSXPiVar('DriveR2') + '/' + path.split(':')[1]
    elif (path.lower().startswith('http') or \
        path.lower().startswith('ftp') or \
        path.lower().startswith('nfs') or \
        path.lower().startswith('smb')):
        urltype = 1 # this is a network path
        newpath = path
    elif basepath.startswith('/'):
        urltype = 0 # this is a local path
        newpath = basepath + '/' + path
        newpath = newpath.replace('//','/')
    else:
        urltype = 1 # this is a network path
        newpath = basepath.rstrip('/') + "/" + path
    return [urltype, newpath]

def msxdos_inihrd(filename, access=mmap.ACCESS_WRITE):
    """Map a disk image for the MSX drives. The mapping is of the image file
    itself, so the MSX's sector writes (dskiow) land directly in the file and
    survive however the server stops.

    This used to map a private staging copy instead, so that on Windows the
    image could be overwritten while mounted; but the copy was only synced
    back on Ctrl+C, so any other stop silently lost everything the MSX had
    saved. On Windows a mounted image cannot be replaced by another program -
    remount it (pset DriveA / reload A:) or stop the server to rebuild it."""
    if not filename or not os.path.exists(filename):
        return RC_FAILED, ''

    size = os.path.getsize(filename)
    if size <= 0:
        return RC_FAILED, ''

    fd = os.open(filename, os.O_RDWR | getattr(os, "O_BINARY", 0))
    try:
        disk = mmap.mmap(fd, size, access=access)
    finally:
        os.close(fd)        # the mapping keeps its own handle
    return RC_SUCCESS, disk

def unmount_drive(disk):
    """Flush and release a mapping returned by msxdos_inihrd(), so a remount
    does not keep the previous image file open."""
    if disk and disk != '':
        try:
            disk.flush()
            disk.close()
        except Exception as e:
            print(f"unmount_drive(): {e}")

def dos83format(fname):
    name = '        '
    ext = '   '

    finfo = fname.split('.')

    name = str(finfo[0]).ljust(8)
    if len(finfo) == 2:
        ext = str(finfo[1]).ljust(3)
    
    return name+ext

def ini_fcb(fname,fsize):
    #print("ini_fcb()")
    
    fpath = fname.split(':')
    if len(fpath) == 1:
        msxfile = str(fpath[0])
        msxdrive = 0
    else:
        msxfile = str(fpath[1])
        drvletter = str(fpath[0]).upper()
        msxdrive = ord(drvletter) - 64

    #convert filename to 8.3 format using all 11 positions required for the FCB
    msxfcbfname = dos83format(msxfile)

    # send FCB structure to MSX
    buf = bytearray()
    buf.extend(msxdrive.to_bytes(1,'little'))
    buf.extend(msxfcbfname.encode())
    rc = sendmultiblock(buf)   
    return rc

def run(cmd = ''):
    #print(f"run(): {cmd}")
    
    global hostType
    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        rc = sendmultiblock("Syntax: run <command> <::> command. To  pipe a command to other, use :: instead of |")
        return RC_FAILED

    cmd = cmd.replace('::','|')
    rc = RC_SUCCESS

    try:
        if hostType == "Windows" and "http" not in cmd:
            cmd = cmd.replace("/", "\\")

        p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
        buf = p.stdout.read().decode()
        err = (p.stderr.read().decode())
        if len(err) > 0 and not ('0K ....' in err): # workaround for wget false positive
            rc = RC_FAILED
            buf = ("Pi:Error - " + str(err))
        elif len(buf) == 0:
            rc = RC_SUCCESS
            buf = "Pi:Ok"
        sendmultiblock(buf.encode())
        return rc
    except Exception as e:
        print("run: exception:"+str(e))
        sendmultiblock(("Pi:Error - "+str(e)).encode())
        return rc

def dir(data):
    #print(f"pdir():{data}")
    
    basepath = getMSXPiVar('PATH')
  
    if not data:
        userPath=''
    else:
        userPath = data
    pathType, path = pathExpander(userPath, basepath)           
    try:
        if pathType == 0:
            if hostType == "Windows":
                run('dir ' + path)
            else:
                run('ls -l ' + path)
        else:
            parser = MyHTMLParser()
            # Bounded: an unreachable host otherwise blocks here for ever, with
            # the MSX waiting for a reply and nothing in the log.
            htmldata = urlopen(path, timeout=HTTP_TIMEOUT).read().decode()
            parser = MyHTMLParser()
            parser.feed(htmldata)
            buf = " ".join(parser.HTMLDATA)
            rc = sendmultiblock(buf.encode())
    except Exception as e:
        sendmultiblock(('Pi:Error - ' + str(e)).encode())

    return RC_SUCCESS

def cd(data):
    #print(f"pcd(): {data}")
    
    rc = RC_SUCCESS
    basepath = getMSXPiVar('PATH') 
    if not data:
        userPath=''
    else:
        userPath = data 
    try:
        if (len(userPath) == 0 or userPath == '' or userPath.strip() == "."):
            rc = sendmultiblock(basepath.encode())
        elif (userPath.strip() == ".."):
            newpath = basepath.rsplit('/', 1)[0]
            if (newpath == ''):
                newpath = '/'
            setMSXPiVar('PATH',newpath)
            rc = sendmultiblock(newpath.encode())
        else:
            pathType, path = pathExpander(userPath, basepath)
            if pathType == 0:
                if (os.path.isdir(path)):
                    setMSXPiVar('PATH',path)
                    rc = sendmultiblock(path.encode())
                else:
                    sendmultiblock("Pi:Error - not a folder".encode())
            else:
                setMSXPiVar('PATH',path)
                rc = sendmultiblock(path.encode())
    except Exception as e:
        print("pcd:"+str(e))
        sendmultiblock(('Pi:Error - ' + str(e)).encode())

    return RC_SUCCESS

def pcopy_handshake() -> tuple[int, int]:
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

PCOPY_CACHE = "/tmp/pcopy_session.bin"
PCOPY_STATE = "/tmp/pcopy_state.txt"
PCOPY_PUT_STATE = "/tmp/pcopy_put_state.txt"
# Upload in progress: (target, temp).  Held in memory so a block does not cost
# a filesystem read; PCOPY_PUT_STATE is the fallback after a restart.
_pcopy_put_paths = None

def _pcopy_read_state():
    """(target, temp) from the state file, or None if there is no session."""
    try:
        if not os.path.exists(PCOPY_PUT_STATE):
            return None
        with open(PCOPY_PUT_STATE, "r") as f:
            parts = [x.strip() for x in f.read().split("\n") if x.strip()]
        if not parts:
            return None
        return (parts[0], parts[1] if len(parts) > 1 else parts[0])
    except OSError:
        return None
def pcopy(msxcmd="pcopy"):
    #print(f"pcopy() called with msxcmd: '{msxcmd}'")

    global psetvar, GLOBALRETRIES, hostType
    basepath = getMSXPiVar('PATH')

    # Helper to transmit error block payload to MSX
    def send_error_block(err_msg, err_code):
        print(f"Pi:Error - {err_msg}")
        rc, msx_blocksize = pcopy_handshake()
        if rc == RC_SUCCESS:
            payload = err_msg.encode('ascii', errors='replace')
            senddata_oneblock(payload, msx_blocksize, err_code, 0)
        return err_code

    # 1. Clean input payload and resolve global pcmd fallback
    cmd_str = msxcmd.strip()
    if cmd_str == "" or cmd_str.lower() == "pcopy":
        pcmd_val = str(globals().get('pcmd', '')).strip()
        if pcmd_val and pcmd_val.lower() != "pcopy":
            cmd_str = pcmd_val

    tokens = cmd_str.split()

    # Remove 'pcopy' prefix if present
    if tokens and tokens[0].lower().startswith("pcopy"):
        parms = tokens[1:]
    else:
        parms = tokens

    if len(parms) < 1:
        return send_error_block("Missing parameters", RC_INVALIDCOMMAND)

    subcmd = parms[0].lower()

    # =========================================================================
    # PHASE 2: READBLOCK (Transfers one block and releases server loop)
    # =========================================================================
    if subcmd == "readblock":
        if not os.path.exists(PCOPY_CACHE) or not os.path.exists(PCOPY_STATE):
            return send_error_block("No active transfer session", RC_FAILED)

        try:
            with open(PCOPY_STATE, "r") as f:
                state_parts = f.read().strip().split(",")
                offset = int(state_parts[0])
                block_index = int(state_parts[1])
        except Exception as e:
            return send_error_block(f"State read error: {str(e)}", RC_FAILED)

        rc, msx_blocksize = pcopy_handshake()
        if rc != RC_SUCCESS:
            print("Pi:Error - Handshake failed during readblock")
            return rc

        filesize = os.path.getsize(PCOPY_CACHE)

        with open(PCOPY_CACHE, "rb") as f:
            f.seek(offset)
            chunk = f.read(msx_blocksize)

        new_offset = offset + len(chunk)
        # Signal RC_SUCCESS on final block, RC_READY if more blocks remain
        header_rc = RC_SUCCESS if new_offset >= filesize else RC_READY

        senddata_oneblock(chunk, msx_blocksize, header_rc, block_index)

        if header_rc == RC_SUCCESS:
            # Transfer finished: Clean up session files
            try:
                os.remove(PCOPY_CACHE)
                os.remove(PCOPY_STATE)
            except OSError:
                pass
        else:
            # Advance state for next readblock request
            next_block_index = (block_index + 1) & 0xFF
            with open(PCOPY_STATE, "w") as f:
                f.write(f"{new_offset},{next_block_index}")

        return RC_SUCCESS

    # =========================================================================
    # UPLOAD: MSX -> Pi.   pcopy A:game.rom game.rom
    # =========================================================================
    # Mirrors the download side: "put" opens the destination and reports
    # whether it could be created, "writeblock" takes one block, "putclose"
    # finishes.  A separate close rather than a last-block flag, because the
    # block protocol carries no header byte in this direction.
    #
    # The destination path is resolved against the MSXPi PATH variable exactly
    # as a download source is, so "pcopy A:game.rom game.rom" lands beside the
    # files a plain "pcopy game.rom" would read.  Local filesystem only - a
    # URL target is rejected rather than silently written somewhere odd.
    if subcmd == "put":
        if len(parms) < 2:
            return send_error_block("Missing destination for put", RC_INVALIDCOMMAND)
        tgt_type, tgt_path = pathExpander(parms[1], basepath)
        if tgt_type != 0:
            return send_error_block("Only local paths can be written", RC_INVALIDCOMMAND)
        # Write to a temporary name; the rename in putclose is what publishes
        # the file.  Truncating the real target here destroyed a verified good
        # copy when a later attempt failed part way - the file was left short
        # but looked finished, and only its sha1 gave it away.  Creating the
        # temp now still surfaces a permissions or missing-directory error
        # while the MSX is still listening for it.
        tmp_path = tgt_path + ".part"
        try:
            with open(tmp_path, "wb"):
                pass
            with open(PCOPY_PUT_STATE, "w") as f:
                f.write(tgt_path + "\n" + tmp_path)
        except Exception as e:
            return send_error_block(f"Cannot create {tmp_path}: {str(e)}", RC_FAILED)
        globals()["_pcopy_put_paths"] = (tgt_path, tmp_path)

        print(f"pcopy: receiving into {tgt_path}")
        rc, msx_blocksize = pcopy_handshake()
        if rc != RC_SUCCESS:
            return rc
        senddata_oneblock(b"OK", msx_blocksize, RC_SUCCESS, 0)
        return RC_SUCCESS

    if subcmd == "writeblock":
        # Paths are cached in memory; the state file is only the fallback for
        # a server restarted mid-transfer.  Re-reading it per block meant one
        # SD-card open for every 8 KB - 64 of them on a 512 KB upload - and
        # any transient filesystem error aborted the whole transfer.
        paths = globals().get("_pcopy_put_paths")
        if paths is None:
            paths = _pcopy_read_state()
            if paths is None:
                return send_error_block("No active upload session", RC_FAILED)
            globals()["_pcopy_put_paths"] = paths
        tmp_path = paths[1]

        # recvdata2_oneblock does its own handshake, matching SENDDATA2 on the
        # MSX side, so nothing is done here before calling it.
        rc, payload = recvdata2_oneblock(MAXBUFSIZE)
        if payload is None:
            print("pcopy: writeblock received nothing (rc=%s)" % hex(rc if rc is not None else 0))
            return RC_CONNERR
        # Logged per block on purpose: without it a failed upload shows only a
        # run of identical "pcopy writeblock" lines, with no way to tell how
        # far it got or whether the blocks were full.  One line per 16 KB.
        print("pcopy: writeblock got %d bytes (rc=%s)" % (len(payload), hex(rc)))
        try:
            with open(tmp_path, "ab") as f:
                f.write(payload)
        except Exception as e:
            print(f"Pi:Error - write failed: {str(e)}")
            return RC_FAILED
        return RC_SUCCESS

    if subcmd == "putclose":
        paths = globals().get("_pcopy_put_paths") or _pcopy_read_state()
        if not paths:
            print("pcopy: putclose with no session - nothing to finalise")
        globals()["_pcopy_put_paths"] = None
        try:
            os.remove(PCOPY_PUT_STATE)
        except OSError:
            pass

        # The rename is what publishes the file.  Until it happens the target
        # keeps whatever it held, so a transfer that died part way cannot pass
        # for a good copy.
        if paths:
            tgt_path, tmp_path = paths
            if os.path.exists(tmp_path):
                try:
                    size = os.path.getsize(tmp_path)
                    os.replace(tmp_path, tgt_path)
                    print(f"pcopy: received {size} bytes into {tgt_path}")
                except OSError as e:
                    print(f"Pi:Error - cannot finalise {tgt_path}: {str(e)}")
        rc, msx_blocksize = pcopy_handshake()
        if rc != RC_SUCCESS:
            return rc
        senddata_oneblock(b"OK", msx_blocksize, RC_SUCCESS, 0)
        return RC_SUCCESS

    # =========================================================================
    # PHASE 1: INIT (Locates, decompresses, caches file & confirms readiness)
    # =========================================================================
    if subcmd == "init":
        parms = parms[1:]
        if len(parms) < 1:
            return send_error_block("Missing source file for init", RC_INVALIDCOMMAND)

    #print(f"pcopy: Init parsed parameters -> {parms}")
    userPath = " ".join(parms)

    # 2. Parse paths with smart source/target auto-detection
    expand = '/z' in userPath.lower()

    if expand:
        src_param = parms[1] if len(parms) > 1 else parms[0]
        tgt_param = parms[2] if len(parms) > 2 else ""
    else:
        src_param = parms[0]
        tgt_param = parms[1] if len(parms) > 1 else ""

    pathType, path = pathExpander(src_param, basepath)

    # Auto-fallback: If src_param doesn't exist on Pi, check if tgt_param does
    if pathType == 0 and not os.path.exists(path) and tgt_param != "":
        alt_type, alt_path = pathExpander(tgt_param, basepath)
        if alt_type == 0 and os.path.exists(alt_path):
            #print(f"pcopy: Swapping inverted parameters -> Source: '{tgt_param}', Target: '{src_param}'")
            src_param, tgt_param = tgt_param, src_param
            pathType, path = alt_type, alt_path

    # 3. Read source file contents
    if pathType == 0:
        try:
            with open(path, mode='rb') as f:
                buf = f.read()
            filesize = len(buf)
        except Exception as e:
            err_code = RC_FILENOTFOUND if "[Errno 2]" in str(e) else RC_FAILED
            return send_error_block(f"File error: {str(e)}", err_code)
    else:
        try:
            urlhandler = urlopen(path, timeout=HTTP_TIMEOUT)
            buf = urlhandler.read()
            filesize = len(buf)
        except Exception as e:
            return send_error_block(f"URL error: {str(e)}", RC_FAILED)

    if filesize == 0:
        return send_error_block("File size is zero bytes", RC_FAILED)

    # 4. Decompress if /z option was specified
    if expand:
        tmpfn0 = path.split('/')
        tmpfn = tmpfn0[-1]
        if hostType == "Windows":
            os.system('del /Q "C:\\tmp\\msxpi\\*"')
        else:
            os.system('rm /tmp/msxpi/* 2>/dev/null')

        with open('/tmp/' + tmpfn, 'wb') as tmpfile:
            tmpfile.write(buf)

        if ".lzh" in tmpfn:
            cmd = 'lha -xfiw=/tmp/msxpi /tmp/' + tmpfn if hostType == "Windows" else '/usr/bin/lhasa -xfiw=/tmp/msxpi /tmp/' + tmpfn
        else:
            cmd = '7z.exe e /tmp/' + tmpfn + ' -aoa -o/tmp/msxpi/' if hostType == "Windows" else '/usr/bin/unar -f -o /tmp/msxpi /tmp/' + tmpfn

        p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
        perror = p.stderr.read().decode()
        rc = p.poll()
        if rc is not None and rc != 0:
            return send_error_block(f"Decompression failed: {perror}", RC_FAILED)

        romfiles = [f for f in os.listdir('/tmp/msxpi') if f.endswith(('.rom', '.ROM'))]
        if romfiles:
            fname1 = '/tmp/msxpi/' + romfiles[0]
            try:
                with open(fname1, mode='rb') as f:
                    buf = f.read()
                filesize = len(buf)
            except Exception as e:
                return send_error_block(f"ROM read error: {str(e)}", RC_FAILED)
        else:
            return send_error_block(f"No ROM file in archive: {perror}", RC_FAILED)

    # 5. Cache processed buffer and state for readblock calls
    with open(PCOPY_CACHE, "wb") as f:
        f.write(buf)

    with open(PCOPY_STATE, "w") as f:
        f.write("0,0")  # initial offset=0, block_index=0

    # 6. Perform handshake and confirm initialization to MSX client
    rc, msx_blocksize = pcopy_handshake()
    if rc != RC_SUCCESS:
        print("Pi:Error - Handshake failed during init")
        return rc

    # Send confirmation block back to MSX
    senddata_oneblock(b"READY", msx_blocksize, RC_SUCCESS, 0)
    #print("pcopy: Initialization complete")
    return RC_SUCCESS
    
def formatrsp(rc,lsb,msb,msg,size=BLKSIZE):
    b = bytearray(size)
    b[0] = rc
    b[1] = lsb
    b[2] = msb
    b[3:len(msg)] = bytearray(msg.encode())
    return b
    
def date(parms = None):
    #print("pdate()")

    pdate = bytearray(8)
    now = datetime.datetime.now()

    # Fill buffer in MSX expected order
    pdate[0] = now.day
    pdate[1] = now.month
    pdate[2] = now.year & 0xFF
    pdate[3] = now.year >> 8
    pdate[4] = now.hour
    pdate[5] = now.minute
    pdate[6] = now.second
    pdate[7] = 0  # hundredths (unused)

    # -----------------------------
    # Debug print (MSX-style)
    # -----------------------------
    #print("Python buffer values before sending:")
    #print(f"buffer[0] Day:     {pdate[0]}")
    #print(f"buffer[1] Month:   {pdate[1]}")
    #print(f"buffer[2] YearLo:  {pdate[2]}")
    #print(f"buffer[3] YearHi:  {pdate[3]}")
    #print(f"buffer[4] Hour:    {pdate[4]}")
    #print(f"buffer[5] Minute:  {pdate[5]}")
    #print(f"buffer[6] Second:  {pdate[6]}")
    #print(f"buffer[7] Sec100:  {pdate[7]}")

    year = pdate[2] | (pdate[3] << 8)
    #print(f"Parsed Date: {pdate[0]:02d}/{pdate[1]:02d}/{year}")
    #print(f"Parsed Time: {pdate[4]:02d}:{pdate[5]:02d}:{pdate[6]:02d}")

    # Now send to MSX
    sendmultiblock(pdate)

def play(data):
    #print(f"pplay(): {data}")
       
    if hostType != "RaspberryPi": 
        sendmultiblock("Command not supported by this platform".encode())
        return RC_SUCCESS

    if not data:
        rc = sendmultiblock("Syntax:\npplay play|loop|pause|resume|stop|getids|getlids|list <filename|processid|directory|playlist|radio>\nExemple: pplay play music.mp3")
        return RC_FAILED
        
    parmslist = data.split(" ")
    cmd = parmslist[0]
    if len(parmslist) > 1:
        parms = data.split(" ")[1].split("\x00")[0]
    else:
        parms = ''

    buf = ''
    try:
        buf = subprocess.check_output(['/home/pi/msxpi/pplay.sh',getMSXPiVar('PATH'),cmd,parms])
        if buf == b'':
            buf = b'\x0a'
        sendmultiblock(buf)
    except subprocess.CalledProcessError as e:
        sendmultiblock(("Pi:Error - "+str(e)).encode())

    return RC_SUCCESS
    
def vol(data=None):
    #print(f"pvol(): {data}")

    if hostType == "RaspberryPi": 
        rc = run("mixer set PCM -- " + data)
        sendmultiblock("Pi:Ok")
        return RC_SUCCESS
    else:
        sendmultiblock("Command not supported by this platform".encode())
    return RC_SUCCESS
    
def pset(data):
    #print(f"pset(): {data}")
    global psetvar, drive0Data, drive1Data

    # Normalize input
    data = data.strip()

    # ---------------------------------------------------------
    # 0. No arguments → list all variables
    # ---------------------------------------------------------
    if not data:
        out = ""
        for name, value in psetvar:
            out += f"{name}={value}\n"
        return sendmultiblock(out.encode())

    # Split into tokens
    parts = data.split()
    cmd = parts[0].lower()

    # ---------------------------------------------------------
    # 1. Global help:  set /h   set /he   set /help
    # ---------------------------------------------------------
    if cmd in ("/h", "/help"):
        helptext = (
            "Syntax:\n"
            "set                     List all variables\n"
            "set varname             Show a single variable\n"
            "set varname value       Set or update variable\n"
            "set varname /d          Delete variable\n"
            "set /h                  Show this help"
        )
        return sendmultiblock(helptext.encode())

    # Now treat first token as variable name
    varname = parts[0]
    varname_upper = varname.upper()

    # ---------------------------------------------------------
    # 2. Single variable display:  set wifi
    # ---------------------------------------------------------
    if len(parts) == 1:
        for name, value in psetvar:
            if name.upper() == varname_upper:
                return sendmultiblock(f"{name}={value}".encode())
        return sendmultiblock(f"{varname} not found".encode())

    # ---------------------------------------------------------
    # 3. Per-variable help:  set wifi /h
    # ---------------------------------------------------------
    if parts[1].lower() in ("/h", "/he", "/help"):
        helptext = (
            f"Help for variable '{varname}':\n"
            "set varname             Show variable\n"
            "set varname value       Set variable\n"
            "set varname /d          Delete variable\n"
        )
        return sendmultiblock(helptext.encode())

    # ---------------------------------------------------------
    # 4. Delete variable:  set wifi /d
    # ---------------------------------------------------------
    if parts[1].lower() in ("/d", "/delete"):
        print(f"Deleting variable {varname}")
        rc = setMSXPiVar(varname, "")  # empty value = delete
        return sendmultiblock("Pi:Ok".encode())

    # ---------------------------------------------------------
    # 5. Set or update variable:  set wifi MYSSID
    # ---------------------------------------------------------
    varvalue = data[len(varname):].strip()

    print(f"Setting variable {varname} to value {varvalue}")
    rc = setMSXPiVar(varname, varvalue)

    # Special cases for drives
    if rc == RC_SUCCESS:
        if varname_upper == 'DRIVEA':
            old = drive0Data
            rc, drive0Data = msxdos_inihrd(varvalue)
            unmount_drive(old)
            updateIniFile(MSXPIHOME + '/msxpi.ini', psetvar)

        elif varname_upper == 'DRIVEB':
            old = drive1Data
            rc, drive1Data = msxdos_inihrd(varvalue)
            unmount_drive(old)
            updateIniFile(MSXPIHOME + '/msxpi.ini', psetvar)

        return sendmultiblock("Pi:Ok".encode())

    return sendmultiblock("Pi:Error".encode())

def setMSXPiVar(pvar='', pvalue=''):
    global psetvar
    #print(f"setMSXPiVar(): var={pvar} value={pvalue}")

    # Normalize name for case-insensitive matching
    pvar_upper = pvar.upper()

    # ---------------------------------------------------------
    # 1. Update or delete existing variable
    # ---------------------------------------------------------
    for i, (name, value) in enumerate(psetvar):
        if name.upper() == pvar_upper:

            # Delete variable if no value provided
            if pvalue == '':
                print(f"Deleting variable {pvar}")
                del psetvar[i]
            else:
                print(f"Updating variable {pvar} to {pvalue}")
                psetvar[i][1] = pvalue

            updateIniFile(MSXPIHOME + '/msxpi.ini', psetvar)
            return RC_SUCCESS

    # ---------------------------------------------------------
    # 2. Add new variable (dynamic growth)
    # ---------------------------------------------------------
    print(f"Adding new variable {pvar}={pvalue}")
    psetvar.append([pvar, pvalue])
    updateIniFile(MSXPIHOME + '/msxpi.ini', psetvar)
    return RC_SUCCESS

def getMSXPiVar(devname = 'PATH'):
    global psetvar
    devval = ''
    idx = 0
    for v in psetvar:
        if devname.upper() ==  psetvar[idx][0].upper():
            devval = psetvar[idx][1]
            break
        idx += 1
    return devval
    
def interfaces_report():
    """One line per interface: name, state, IPv4 address - for a 40-column MSX.

    This used to be `ip a` filtered through
    `grep '^1\\|^2\\|^3\\|^4\\|inet' | grep -v inet6`, which keeps the header
    line only for interfaces numbered 1 to 4. msxpi0 is recreated every time
    the TAP is rebuilt, and its index climbs with each one, so once it passed 4
    its header vanished while its "inet" line stayed - leaving an address
    hanging under the previous interface, which reads as corrupted output.
    Nothing about an interface's index says anything useful anyway.

    `ip -o` keeps each record on ONE line, so there is nothing to reassemble
    and no wrapped line to mis-parse.
    """
    def ip_out(args):
        try:
            done = subprocess.run(["ip", "-o"] + args, stdout=PIPE,
                                  stderr=STDOUT, text=True, timeout=10)
            return done.stdout if done.returncode == 0 else ""
        except Exception as exc:
            print(f"interfaces_report: {exc}")
            return ""

    state = {}
    for line in ip_out(["link", "show"]).splitlines():
        # "2: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ..."
        parts = line.split(":", 2)
        if len(parts) < 3:
            continue
        name = parts[1].strip().split("@")[0]
        flags = parts[2]
        state[name] = "up" if ",UP" in flags or "<UP" in flags else "down"

    addrs = {}
    for line in ip_out(["-4", "addr", "show"]).splitlines():
        # "2: wlan0    inet 192.168.1.239/24 brd ... scope global wlan0\"
        fields = line.split()
        if len(fields) < 4 or fields[2] != "inet":
            continue
        addrs.setdefault(fields[1].split("@")[0], []).append(fields[3])

    if not state and not addrs:
        return "Pi:could not read the interfaces"

    report = []
    for name in state or addrs:
        for addr in addrs.get(name, ["-"]):
            report.append(f"{name:<8.8} {state.get(name, '?'):<4} {addr}")
    return "\r\n".join(report)


def wifi(cmd):
    #print(f"pwifi(): {cmd}")
    global psetvar
    wifissid = getMSXPiVar('WIFISSID')
    wifipass = getMSXPiVar('WIFIPWD')
    wificountry = getMSXPiVar('WIFICOUNTRY')

    if (cmd[:2] == "/h"):
        sendmultiblock("Pi:Usage:\npwifi display | set".encode())
        return RC_SUCCESS

    if (cmd[:1] == "s" or cmd[:1] == "S"):
        if hostType == "RaspberryPi":
            wifisetcmd = 'sudo nmcli device wifi connect "' + wifissid + '" password "' + wifipass + '"'
            run(wifisetcmd)
        else:
            sendmultiblock(b'Parameter not supported in this platform')
    else:
        if hostType == "RaspberryPi":
            sendmultiblock(interfaces_report().encode())
        else:
            run("ipconfig")
    
    return RC_SUCCESS

def ver(parms = None):
    #print("pver()")
    global version,build
    ver = "MSXPi Server Version "+version+" Build "+ BuildId + "\n";
    print("Sending version info:",ver)
    RC = sendmultiblock(ver.encode())
    #print(f"pver(): returning rc = {hex(rc)}")
    return rc
           
def dosinit(parms = None):
    #print("dosinit()")    
    global msxdos1boot
        
    rc,data = recvdata2()
    if rc == RC_SUCCESS:
        flag = data.decode().split("\x00")[0]
        if flag == '1':
            dskioini()
        else:
            msxdos1boot = False
 
    return rc
    
def dskioini(parms = None):
    #print("dskioini() - MSX-DOS Boot Starting.")

    global msxdos1boot,sectorInfo,drive0Data,drive1Data

    # Initialize disk system parameters
    msxdos1boot = True
    sectorInfo = [0,0,0,0]
    # Load the disk images into a memory mapped variable
    rc , drive0Data = msxdos_inihrd(getMSXPiVar('DriveA'))
    rc , drive1Data = msxdos_inihrd(getMSXPiVar('DriveB'))

def reload(parms = None):
    """Re-opens the DriveA/DriveB disk image file (mmap) from its
    current path, without needing to restart the server. Mirrors what
    'pset DriveA <path>' already does when the variable is (re)assigned
    (msxdos_inihrd() re-mmaps the file) - useful after rebuilding a disk
    image on disk, since the existing mmap otherwise keeps the file
    handle open and doesn't pick up changes (and blocks overwriting the
    file from outside). Usage: reload A:  or  reload B:
    """
    #print(f"reload(): {parms!r}")
    global drive0Data, drive1Data

    driveLetter = (parms or "").strip().upper().rstrip(":").rstrip("\x00")

    if driveLetter == "A":
        varname, varname_upper = "DriveA", "A"
    elif driveLetter == "B":
        varname, varname_upper = "DriveB", "B"
    else:
        return sendmultiblock(b"Pi:Error - usage: reload A: or reload B:")

    path = getMSXPiVar(varname)
    if not path:
        return sendmultiblock(f"Pi:Error - {varname} is not set".encode())

    rc, data = msxdos_inihrd(path)
    if rc != RC_SUCCESS:
        return sendmultiblock(f"Pi:Error - failed to reload {path}".encode())

    # Release the previous mapping only once the new one is in place, so a
    # failed reload leaves the drive usable.
    if varname_upper == "A":
        unmount_drive(drive0Data)
        drive0Data = data
    else:
        unmount_drive(drive1Data)
        drive1Data = data

    print(f"reload(): {varname} reloaded from {path}")
    return sendmultiblock(f"Pi:Ok - Drive {varname_upper}: reloaded from {path}".encode())

def dskior(parms = None):
    #print("dskiords()")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data,SECTORSIZE
    if not msxdos1boot:
        dskioini()
        
    initdataindex = sectorInfo[3]*SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    #print("dskiords:deviceNumber=",sectorInfo[0])
    #print("dskiords:numsectors=",sectorInfo[1])
    #print("dskiords:mediaDescriptor=",sectorInfo[2])
    #print("dskiords:initialSector=",sectorInfo[3])
    #print("dskiords:blocksize=",SECTORSIZE)
    
    # Multi-sector reads are the interesting case: MSX-DOS asks for one sector
    # at a time for directory and FAT access, but uses B>1 for the body of a
    # large file, so a defect in the per-sector handshake only shows up on big
    # programs. Off by default - a line per sector buries everything else in
    # the log during a copy - so turn it on when chasing one:
    #     MSXPI_PROFILE=1 python3 msxpi-server.py
    if _PROFILE:
        print("dskiords: drive=%d sector=%d count=%d" %
              (sectorInfo[0], sectorInfo[3], numsectors))

    while sectorcnt < numsectors:
        #print("dskiords:",sectorcnt)
        if sectorInfo[0] == 0:
            buf = drive0Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)]
        else:
            buf = drive1Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)]

        rc = sendmultiblock(buf)
        sectorcnt += 1
        
        if  rc == RC_SUCCESS:
            pass
            #print("dskiords: checksum is a match")
        else:
            # WHICH sector failed, not merely that one did: the distinction
            # between "the first sector of a multi-sector call" and "a later
            # one" separates a transport-timing fault from a handshake that
            # cannot survive more than one sector per call.
            print("dskiords: checksum error on sector %d of %d (abs %d), rc=%s"
                  % (sectorcnt, numsectors, sectorInfo[3] + sectorcnt - 1, rc))
            break
 
def dskiow(parms = None):
    #print("dskiowrs()")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data,SECTORSIZE
    if not msxdos1boot:
        dskioini()
        
    initdataindex = sectorInfo[3]*SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    #print("dskiowrs:deviceNumber=",sectorInfo[0])
    #print("dskiowrs:numsectors=",sectorInfo[1])
    #print("dskiowrs:mediaDescriptor=",sectorInfo[2])
    #print("dskiowrs:initialSector=",sectorInfo[3])
    #print("dskiowrs:blocksize=",SECTORSIZE)
    
    while sectorcnt < numsectors:
        rc,buf = recvdata2()
        if  rc == RC_SUCCESS:
            #print("dskiowrs: checksum is a match")
            if sectorInfo[0] == 0:
                drive0Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = buf
            else:
                drive1Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = buf
            sectorcnt += 1
        else:
            print("dskiowrs: checksum error")
            break

    # The drive maps the image file itself; push the MSX's writes to disk
    # now rather than whenever the OS gets round to it.
    disk = drive0Data if sectorInfo[0] == 0 else drive1Data
    if sectorcnt > 0 and disk and disk != '':
        disk.flush()
                  
def dskios(parms = None):
    #print("dskiosct()")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data,SECTORSIZE
    if not msxdos1boot:
        dskioini()
  
    rc,buf = recvdata2(5)
    sectorInfo[0] = buf[0]
    sectorInfo[1] = buf[1]
    sectorInfo[2] = buf[2]
    byte_lsb = buf[3]
    byte_msb = buf[4]
    sectorInfo[3] = byte_lsb + 256 * byte_msb
    if  rc == RC_SUCCESS:
        pass
    #    print("dskiosct: checksum is a match")
    else:
        print("dskiosct: checksum error")
          
    #print("dskiosct:deviceNumber=",sectorInfo[0])
    #print("dskiosct:numsectors=",sectorInfo[1])
    #print("dskiosct:mediaDescriptor=",sectorInfo[2])
    #print("dskiosct:initialSector=",sectorInfo[3])
       
# The v1.6 driver sends the short names; every ROM before it sends these.
# Keeping both costs three lines and lets a server upgraded ahead of the EEPROM
# - the usual order, since one is a file copy and the other is a reflash - go on
# serving an older ROM. The reverse pairing cannot be rescued from here: a v1.6
# ROM against a pre-1.6 server fails on the name, which is a better failure than
# the silent one it would otherwise hit (that server reads the burst request as
# a 33280-byte buffer and answers with an ordinary block).
dskiords = dskior
dskiowrs = dskiow
dskiosct = dskios


def recvdata2(maxbufsize = 8192):
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
        if burst and not globals().get('_burst_in_announced'):
            globals()['_burst_in_announced'] = True
            print("recvdata2(): MSX sends /WAIT burst payloads - receiving them")

        # --- block_index ---
        rc, block_index = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # Validate block index
        if block_index != expected_block_index:
            # Protocol drift
            print(f"recvdata2: block index {block_index}, expected {expected_block_index} "
                  f"(header_rc {header_rc:#04x}, len {length}, burst {burst}) - out of step")
            return (RC_CONNERR, None)

        # Capacity checks
        if length > block_max:
            # MSX tried to send more than negotiated / allowed
            print(f"recvdata2: block of {length} bytes exceeds the negotiated {block_max}")
            return (RC_CONNERR, None)
        if len(data) + length > maxbufsize:
            # Would overflow caller's max buffer
            print(f"recvdata2: {len(data)}+{length} bytes exceeds the {maxbufsize}-byte buffer")
            return (RC_CONNERR, None)

        # --- Payload ---
        rc, payload = SPI_BurstIn(length) if burst else SPI_ReadPayload(length)
        if rc != RC_SUCCESS:
            print(f"recvdata2: payload read failed rc={rc:#04x} "
                  f"({'burst' if burst else 'polled'}, block {block_index}, {length} bytes)")
            return (RC_CONNERR, None)
        chksum = sum(payload)

        # --- Local checksum (Python receiver) ---
        right = chksum & 0xFF
        left  = (chksum >> 8) & 0xFF
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
            print(f"recvdata2: checksum mismatch, block {block_index}, {length} bytes, "
                  f"{'burst' if burst else 'polled'}: MSX {msxsum:#04x}, Pi {local_sum:#04x} - MSX resends")
            # DIAGNOSTIC (not for release): keep what a failed burst delivered,
            # to line it up against the source file - a duplicated byte shows
            # as a repeat at one offset, line noise as changed bits.
            if burst:
                try:
                    n = globals().get('_burst_dump_n', 0) + 1
                    globals()['_burst_dump_n'] = n
                    dump = f"/tmp/msxpi-burst-mismatch-{n}.bin"
                    with open(dump, 'wb') as f:
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
            print(f"recvdata2: status handshake failed after block {block_index} "
                  f"(rc={rc:#04x}, got {ack!r}, want READY_ACK {READY_ACK:#04x})")
            return (RC_HANDSHAKEERR, None)

        # If this was the last block, we're done
        if header_rc == RC_SUCCESS:
            return (RC_SUCCESS, bytes(data))

        # Otherwise header_rc == RC_READY: loop for next block

def senddata(header_rc, payload):
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
        block_bytes = payload[offset:offset + block_size]
        local_sum = compute_checksum(block_bytes)

        is_last_block = (offset + block_size >= total_size)
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

def recvdata2_oneblock(maxbufsize):
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
        left  = (chksum >> 8) & 0xFF
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
        return (RC_SUCCESS, bytes(payload))   # last block

    if header_rc == RC_READY:
        return (RC_READY, bytes(payload))     # more blocks coming

    return (RC_CONNERR, None)                 # unexpected header

def senddata_oneblock(payload: bytes, msx_blocksize: int, header_rc: int, block_index: int = 0,
                      burst: bool = False) -> int:
    #print(f"senddata_oneblock(): Sending block {block_index}, header_rc={hex(header_rc)}, maxsize={msx_blocksize}")
    length = len(payload)
    if length > msx_blocksize:
        return RC_INVALIDDATASIZE
    # A burst block says so in bit 15 of its length; the MSX then reads the
    # payload with /WAIT (INIR) instead of byte by byte. Only when it asked,
    # and only for whole 256-byte runs (a 512-byte sector): the ROM's burst
    # loop has no room for a remainder. Anything else goes byte by byte.
    wire_length = length | BURST_FLAG if burst and length and not length % 256 else length

    # 1. Initial handshake: MSX -> READY, Python -> READY_ACK
    # Is performed by sendmultiblock() once before calling this function.
    
    # 2. Send exactly one block with retries
    attempts = 0
    #print("senddata_oneblock(): Sending block data with retries if needed")
    while True:
        # header_rc
        #print(f"senddata_oneblock(): sending header_rc={hex(header_rc)}")
        rc, _ = SPI_ByteTransfer(header_rc)
        if rc != RC_SUCCESS:
            #print("senddata_oneblock(): FAILED sending header_rc")
            return RC_CONNERR
        #print("senddata_oneblock(): header_rc sent OK")

        # length low/high
        rc, _ = SPI_ByteTransfer(wire_length & 0xFF)
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending length low byte")
            return RC_CONNERR
        rc, _ = SPI_ByteTransfer((wire_length >> 8) & 0xFF)
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending length high byte")
            return RC_CONNERR
        #print(f"senddata_oneblock(): length={length} sent OK")

        # block_index
        rc, _ = SPI_ByteTransfer(block_index & 0xFF)
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending block_index")
            return RC_CONNERR
        #print(f"senddata_oneblock(): block_index={block_index} sent OK, starting payload ({length} bytes)")

        # payload
        chksum = sum(payload)
        rc = SPI_BurstOut(payload) if wire_length & BURST_FLAG else SPI_WritePayload(payload)
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending payload")
            return RC_CONNERR

        #print(f"senddata_oneblock(): payload complete, {length} bytes sent")

        # local checksum
        right = chksum & 0xFF
        left  = (chksum >> 8) & 0xFF
        local_sum = (right + left) & 0xFF

        # send checksum
        rc, _ = SPI_ByteTransfer(local_sum)
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED sending local checksum")
            return RC_CONNERR
        #print(f"senddata_oneblock(): local checksum={local_sum} sent, waiting for MSX checksum")

        # receive MSX checksum
        rc, msxsum = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            print("senddata_oneblock(): FAILED receiving MSX checksum")
            return RC_CONNERR

        #print(f"senddata_oneblock(): local checksum={local_sum}, MSX checksum={msxsum}")
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
    #print("senddata_oneblock(): Performing pos-transfer status handshake")
    rc, ready = SPI_ByteTransfer()
    #print(f"senddata_oneblock(): MSX Handshake = {ready}")
    if rc != RC_SUCCESS:
        return RC_HANDSHAKEERR
    if ready != READY:
        return RC_HANDSHAKEERR

    rc, status_from_msx = SPI_ByteTransfer()
    #print(f"senddata_oneblock(): MSX Status = {status_from_msx}")
    if rc != RC_SUCCESS:
        return RC_CONNERR
    if status_from_msx != RC_SUCCESS:
        return RC_CONNERR

    # send READY_ACK
    #print("senddata_oneblock(): Sending READY_ACK to MSX")
    SPI_ByteTransfer(READY_ACK)

    # 4. Interpret header_rc (what we told MSX)
    if header_rc == RC_SUCCESS:
        return RC_SUCCESS   # last block
    if header_rc == RC_READY:
        return RC_READY     # more blocks follow
    return RC_CONNERR       # unexpected header


def PerformHandshake():
    # 1. Initial handshake: MSX -> READY, Python -> READY_ACK
    #print("PerformHandshake(): Waiting for READY from MSX")
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
            print(f"PerformHandshake(): discarded stray byte {hex(byte)} while waiting for READY")

    # Receive msx_blocksize
    #print("PerformHandshake(): Receiving msx_blocksize from MSX")
    rc, low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_CONNERR, 0
    rc, high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_CONNERR, 0

    msx_blocksize = low | (high << 8)
    #print(f"PerformHandshake(): msx_blocksize={msx_blocksize}")

    return RC_SUCCESS, msx_blocksize

def sendmultiblock(payload: bytes, header_rc = None):
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
    if burst and not globals().get('_burst_announced'):
        globals()['_burst_announced'] = True
        print("sendmultiblock(): MSX asked for /WAIT burst payloads - enabled")

    offset = 0
    block_index = 0
    #print(f"sendmultiblock(): Sending {(total_len/msx_blocksize)} blocks of {msx_blocksize} bytes")
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
        #print(f"sendmultiblock(): Sending block {block_index}, header_rc={hex(block_rc)}, length={len(block)}, MSX max blocksize = {msx_blocksize})")
        rc = senddata_oneblock(block, msx_blocksize, block_rc, block_index, burst)
        if rc not in (RC_SUCCESS, RC_READY):
            # Any error aborts the whole transfer
            return rc

        # Advance to next block
        offset = end
        block_index += 1

    return RC_SUCCESS

def readParameters(errorMsg, needParm=False):
    #print("readparms():")
    rc, data = recvdata2()

    if rc != RC_SUCCESS:
        print(f"Pi:Error reading parameters")
        encodederrorMsg = ('Pi:Error reading parameters').encode()
        sendmultiblock(encodederrorMsg)
        return RC_FAILED, None

    parms = data.decode().split("\x00")[0].strip()
    if needParm and not parms:
        print(f"Pi:Error - {errorMsg}")
        encodederrorMsg = ('Pi:Error - ' + errorMsg).encode()
        sendmultiblock(encodederrorMsg)
        return RC_FAILED, None

    #print(f"Parameters:{parms}")
    return RC_SUCCESS, parms

def q(parm=None):
    """Client-side quit notification (see sendQuit() in msxarch.c/p.c). The
    client sends this and, on most paths, exits back to DOS immediately
    afterward without waiting for/completing a reply - so this must return
    None (no sendmultiblock reply attempted). Previously there was no "q"
    handler at all, so this hit the KeyError/"Unknown command" path, which
    tried to sendmultiblock() an error string to a client that had already
    gone away - leaving the server mid-handshake with nobody listening,
    corrupting the next session's protocol state (surfaced as garbage
    checksums, a forced reconnect, and a "Disk error reading drive A" on
    whatever ran next)."""
    print("q(): client quit")

def restart(parm=None):
    #print("prestart()")
    if hostType == "RaspberryPi":
        print("Restarting MSXPi Server")
        sendmultiblock(b'Pi:Ok')
        exitDueToSyncError()
    else:
        print("Command not supported by this platform")
        sendmultiblock(b'Command not supported by this platform')
        
TCPIP_SETUP = "/home/pi/msxpi/msxpi-tcpip-setup.sh"


def _eth_relink():
    """Re-attach the Ethernet link after the TAP device has been replaced.

    msxpi-tcpip-setup.sh deletes and recreates msxpi0, which leaves the
    shuttle holding a file descriptor to a device that no longer exists - it
    reads and writes without error and carries nothing. Nothing short of
    reopening recovers from that, so netreset() does it here rather than
    telling the user to restart the server.
    """
    global _eth_handle, _eth_tap_retry_at
    if _eth_mod is None or _eth_shuttle is None:
        return None                 # nothing attached yet: first opcode will
    old = _eth_shuttle.link
    try:
        link = _eth_mod.TapLink()
    except Exception as exc:
        print(f"eth: TAP still unavailable after netreset ({exc})")
        _eth_tap_retry_at = 0.0      # let the opcode path keep trying
        return False
    link.enabled = old.enabled
    link.filters = old.filters
    _eth_shuttle.link = link
    old.close()
    _eth_note_link(link)
    _eth_handle = _eth_shuttle.handle
    print("eth: TAP device reattached after netreset", flush=True)
    return True


def _eth_release():
    """Let go of msxpi0 so the setup script can actually delete it.

    `ip tuntap del` does NOT remove a device that a process still has open: it
    clears the persist flag and the device survives, with its original owner,
    until that descriptor is closed. The server is exactly such a process, so
    a netreset that ran the script first would ask the kernel to delete a
    device it was itself holding - the delete "succeeded", the old device
    stayed, and the rebuild reconfigured the very device the server could not
    open. Drop to MockLink first: opcodes keep being answered while the
    network is being rebuilt, and netreset reattaches afterwards.
    """
    global _eth_handle
    if _eth_mod is None or _eth_shuttle is None:
        return
    old = _eth_shuttle.link
    if isinstance(old, _eth_mod.MockLink):
        return
    mock = _eth_mod.MockLink()
    mock.enabled = old.enabled
    mock.filters = old.filters
    _eth_shuttle.link = mock
    old.close()
    _eth_note_link(mock)
    _eth_handle = _eth_shuttle.handle
    print("eth: released msxpi0 for netreset", flush=True)


def netreset(parm=None):
    """Rebuild the Pi's MSX networking from scratch, on demand from the MSX.

    For the case this cannot be designed away: the Pi boots, msxpi-monitor
    starts msxpi-tcpip-setup.sh in the background, and the Pi has no default
    route yet - so there is no uplink to NAT to, the script gives up, and the
    MSX has no network until somebody logs into the Pi. Now "p netreset" does
    the whole sequence: tear down the TAP and the iptables rules, run the setup
    again (new uplink, new TAP owned by the server's user, fresh NAT), and
    reopen the link so the running server picks up the new device.

    An optional parameter is how many seconds to wait for a default route
    (default 15, bounded because the MSX is sitting waiting for the reply).
    """
    if hostType != "RaspberryPi":
        return "Command not supported by this platform"
    if not os.path.isfile(TCPIP_SETUP):
        return f"Pi:{TCPIP_SETUP} missing"

    wait = 15
    if parm:
        try:
            wait = max(1, min(60, int(parm.split()[0])))
        except ValueError:
            pass

    # Before the script runs, not after: see _eth_release().
    _eth_release()

    # A MINIMAL environment, not os.environ: the script takes TAP, TAP_IP,
    # MSX_IP, PREFIX, MTU, TAP_USER and UPLINK from the environment, so
    # anything that happened to be set for the server - by the unit file, the
    # monitor, or whoever started it by hand - would silently reconfigure the
    # network differently here than at boot. Only WAIT_SECS is ours to pass.
    env = {"PATH": os.environ.get("PATH", "/usr/sbin:/usr/bin:/sbin:/bin"),
           "WAIT_SECS": str(wait)}
    report = []
    for phase in ("down", "up"):
        try:
            done = subprocess.run(["sudo", TCPIP_SETUP, phase], env=env,
                                  stdout=PIPE, stderr=STDOUT, text=True,
                                  timeout=wait + 60)
        except Exception as exc:
            return f"Pi:netreset {phase} failed: {exc}"
        out = done.stdout or ""
        print(f"netreset {phase}: rc={done.returncode}\n{out}", flush=True)
        if done.returncode != 0:
            if phase == "down":
                # Teardown failing is not a reason to stop: it exits non-zero
                # when there is no default route yet, which is precisely the
                # situation this command exists for. Let "up" report the
                # real problem.
                continue
            # The script says why on its first line or two - pass that on
            # rather than a bare exit code, since "no default route" is the
            # expected answer when this is run too early.
            global _eth_tap_retry_at
            _eth_tap_retry_at = 0.0     # stale TAP: let the opcode path retry
            why = " ".join(out.split())[:70] or f"exit {done.returncode}"
            return f"Pi:netreset {phase}: {why}"
        if phase == "up":
            # Only the lines worth 40 columns on an MSX screen.
            for line in out.splitlines():
                if line.startswith(("uplink:", "created ", "msxpi0 up:",
                                    "NAT:", "dns:", "WARN")) \
                        or "recreating" in line:
                    report.append(line.strip())

    state = _eth_relink()
    if state is None:
        report.append("link: idle, attaches on first use")
    elif state:
        report.append("link: TAP reattached")
    else:
        report.append("link: TAP unavailable - check owner")
    return "\r\n".join(report) if report else "Pi:netreset done"


def tcpip(parm=None):
    """Alias for netreset - the script is msxpi-tcpip-setup.sh."""
    return netreset(parm)


# Run as one "sudo sh -c" so a single sudoers rule covers it. Works with
# NetworkManager (Bookworm) and with dhcpcd/wpa_supplicant (older images);
# each tool is skipped if absent. Every step is "|| true": a wlan0 in a bad
# state is exactly when individual steps fail, and the next step may still
# recover it.
_WLANRESET_SCRIPT = r"""
IF=wlan0
has() { command -v "$1" >/dev/null 2>&1; }
svc_active() { has systemctl && systemctl is-active --quiet "$1" 2>/dev/null; }
svc_enabled() { has systemctl && systemctl is-enabled --quiet "$1" 2>/dev/null; }

# Decide once who owns wlan0, so the teardown never pokes a manager that is
# not in charge (e.g. a leftover dhcpcd binary on a NetworkManager image).
#   nm       - NetworkManager (Bookworm and newer, or installed by hand)
#   dhcpcd   - dhcpcd + wpa_supplicant hook (Bullseye and older)
#   dhclient - ifupdown/dhclient
#   none     - nothing recognised: link and radio cycle only
if has nmcli && svc_active NetworkManager; then MGR=nm
elif has dhcpcd && { svc_active dhcpcd || svc_enabled dhcpcd; }; then MGR=dhcpcd
elif has dhclient; then MGR=dhclient
else MGR=none
fi
echo "wlanreset: manager=$MGR"

# --- tear down ---
case $MGR in
    nm)       nmcli device disconnect $IF || true ;;
    dhcpcd)   dhcpcd -k $IF >/dev/null 2>&1 || true ;;
    dhclient) dhclient -r $IF || true ;;
esac
ip addr flush dev $IF || true
ip link set $IF down || true

# --- radio off/on: forces the driver to drop the association completely ---
[ $MGR = nm ] && { nmcli radio wifi off || true; }
has rfkill && { rfkill block wifi || true; }
sleep 2
has rfkill && { rfkill unblock wifi || true; }
[ $MGR = nm ] && { nmcli radio wifi on || true; }

ip link set $IF up || true
sleep 2

# --- bring back and request a lease ---
case $MGR in
    nm)
        nmcli device set $IF managed yes || true
        # Connect can race the radio coming back; retry a few times.
        for i in 1 2 3; do
            nmcli device connect $IF && break
            sleep 3
        done
        ;;
    dhcpcd)
        # dhcpcd starts wpa_supplicant from its 10-wpa_supplicant hook;
        # "dhcpcd -k" may have stopped it and a plain rebind does not
        # restart it - a full service restart does.
        if svc_enabled dhcpcd || svc_active dhcpcd; then
            systemctl restart dhcpcd || true
        else
            dhcpcd $IF || true
        fi
        sleep 3
        has wpa_cli && { wpa_cli -i $IF reconfigure || true; }
        ;;
    dhclient)
        has wpa_cli && { wpa_cli -i $IF reconfigure || true; }
        dhclient $IF || true
        ;;
esac
exit 0
"""


def _wlan0_ipv4():
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr", "show", "dev", "wlan0"],
                             stdout=PIPE, stderr=STDOUT, text=True,
                             timeout=5).stdout or ""
    except Exception:
        return None
    for line in out.split("\n"):
        parts = line.split()
        if "inet" in parts:
            return parts[parts.index("inet") + 1]
    return None


def wlanreset(parm=None):
    """Completely reset wlan0 so it gets a fresh DHCP lease from the router.

    Drops the lease, flushes addresses, takes the link down, cycles the WiFi
    radio (rfkill / nmcli), brings the link up and asks NetworkManager, dhcpcd
    or dhclient - whichever the image uses - to reconnect. Then waits for an
    IPv4 address.

    Does not touch msxpi0 or NAT: if the uplink address changed, run
    "p netreset" afterwards.

    Optional parameter: seconds to wait for an address (default 30, max 90).
    """
    if hostType != "RaspberryPi":
        return "Command not supported by this platform"

    wait = 30
    if parm:
        try:
            wait = max(5, min(90, int(parm.split()[0])))
        except ValueError:
            pass

    try:
        done = subprocess.run(["sudo", "sh", "-c", _WLANRESET_SCRIPT],
                              stdout=PIPE, stderr=STDOUT, text=True,
                              timeout=60)
        print(f"wlanreset: rc={done.returncode}\n{done.stdout or ''}", flush=True)
    except Exception as exc:
        return f"Pi:wlanreset failed: {exc}"

    deadline = time.time() + wait
    addr = _wlan0_ipv4()
    while not addr and time.time() < deadline:
        time.sleep(1)
        addr = _wlan0_ipv4()

    if addr:
        return f"wlan0: {addr}"
    return f"Pi:wlanreset: no IPv4 on wlan0 after {wait}s"


def reboot(parm=None):
    #print("preboot()")
    if hostType == "RaspberryPi":
        print("Rebooting Raspberry Pi")
        os.system("sudo reboot")
    else:
        print("Command not supported by this platform")
        sendmultiblock(b'Command not supported by this platform')
        
def shut(parm=None):
    """Shut the Raspberry Pi down. Sent by "p shut", and by msxarch once a game
    is fully loaded, right before it starts the game, when msxarch.ini has
    rebootAfterRomLoad=yes.

    For interactive "p shut" the reply goes out FIRST and the MSX waits for it,
    so the exchange is complete before anything else happens.  msxarch uses
    "shut nowait" because the game is already staged and the launch path should
    not perform another receive/print before jumping into the ROM. Raspberry Pi
    ONLY: on any other host, the no-reply form is a logged no-op and the
    interactive form returns an unsupported-platform message."""
    #print("pshut()")
    no_reply = (parm or "").strip().lower() in ("nowait", "noack", "quiet")
    if hostType == "RaspberryPi" and platform.system() == "Linux":
        if not no_reply:
            sendmultiblock(b"OK")
        print("Shutting down Raspberry Pi in 2 seconds")
        subprocess.Popen("sleep 2; sudo shutdown -h now", shell=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    else:
        print("Command not supported by this platform")
        if not no_reply:
            sendmultiblock(b'Command not supported by this platform')

def button_handler(channel):
    start = time.time()
    # Wait for release
    while GPIO.input(RPI_SHUTDOWN) == GPIO.LOW:
        time.sleep(0.01)
    duration = time.time() - start

    if duration >= 3:
        print("Shutdown triggered")
        os.system("sudo shutdown -h now")
    else:
        print("Reboot triggered")
        os.system("sudo reboot")

   
def exitDueToSyncError():
    print("Sync error. Recycling MSXPi-Server")
    GPIO.cleanup() # cleanup all GPIO
    os.system("/home/pi/msxpi/kill.sh")

def updateIniFile(fname,memvar):
    f = open(fname, 'w')
    for v in memvar:
        f.writelines('var '+v[0]+'='+v[1]+'\n')
    f.close()
    
def chatgpt(query):
    #print("chatgpt()")
    print(query)
    api_key = getMSXPiVar('OPENAIKEY')
    if not api_key or api_key == "Your OpenAI API Key":
        print('Pi:Error - OPENAIKEY is not defined. Define your key with PSET or add to msxpi.ini')
        sendmultiblock(b'Pi:Error - OPENAIKEY is not defined. Define your key with PSET or add to msxpi.ini')
        return RC_FAILED

    model_engine = "gpt-3.5-turbo"
    url = "https://api.openai.com/v1/chat/completions"

    try:
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "model": model_engine,
            "messages": [
                {"role": "user", "content": query}
            ]
        }
        
        response = requests.post(url, headers=headers, json=payload, timeout=HTTP_TIMEOUT)
        openai_response = response.json()
        if "choices" in openai_response:
            response_text = openai_response["choices"][0]["message"]["content"]
            sendmultiblock(response_text.encode())
        else:
            sendmultiblock(openai_response.encode())
    except Exception as e:
        error_msg = f"Pi:Error - {str(e)}"
        print(error_msg)
        sendmultiblock(error_msg.encode())

ROMDB_DEFAULT_URL = "https://raw.githubusercontent.com/costarc/openMSX/master/share/softwaredb.xml"
ROMDB_CACHE_DAYS = 30
_romdb = None


def get_romdb():
    """openMSX's share/softwaredb.xml, indexed by SHA-1 (see load_romdb in
    mapper_detect.py). ROMDB in msxpi.ini may be a URL or a local path; a URL
    is cached as MSXPIHOME/softwaredb.xml and refreshed every ROMDB_CACHE_DAYS,
    and a failed refresh keeps using the cached copy. With no database at all
    the caller falls back to detect_mapper()."""
    global _romdb
    if _romdb:
        return _romdb
    src = getMSXPiVar('ROMDB') or ROMDB_DEFAULT_URL
    text = None
    try:
        if src.startswith(("http://", "https://")):
            cache = os.path.join(MSXPIHOME, "softwaredb.xml")
            fresh = os.path.exists(cache) and \
                time.time() - os.path.getmtime(cache) < ROMDB_CACHE_DAYS * 86400
            if not fresh:
                try:
                    r = requests.get(src, timeout=30)
                    r.raise_for_status()
                    os.makedirs(MSXPIHOME, exist_ok=True)
                    with open(cache, "wb") as f:
                        f.write(r.content)
                except Exception as e:
                    print(f"ROM database download failed ({e}); using the cached copy if any")
            if os.path.exists(cache):
                with open(cache, encoding="utf-8", errors="ignore") as f:
                    text = f.read()
        else:
            with open(src, encoding="utf-8", errors="ignore") as f:
                text = f.read()
    except Exception as e:
        print(f"ROM database unavailable ({e}); falling back to mapper detection")
    _romdb = load_romdb(text) if text else {}
    print(f"ROM database: {len(_romdb)} entries from {src}")
    return _romdb


def is_local_path(s: str) -> bool:
    """A repository entry is a local filesystem path (e.g. /home/roms or
    C:\\Users\\roniv\\Dev\\MSX\\gameroms) rather than an HTTP(S) archive URL
    if it doesn't start with a scheme. Lets msxarchive() browse/load ROMs
    straight off disk where the server runs, with no local web server
    needed."""
    return not (s.startswith("http://") or s.startswith("https://"))


def _rmtree_force(path):
    """shutil.rmtree that also removes read-only files (Windows refuses to
    delete them with 'Access is denied'). Missing path is not an error."""
    def _onerror(func, p, exc_info):
        os.chmod(p, 0o666)
        func(p)
    if os.path.exists(path):
        shutil.rmtree(path, onerror=_onerror)


def fetch_and_uncompress(url: str):
    """
    Download a compressed file from URL into /tmp/msxpi (cache), or - if
    url is a local filesystem path - copy it into the same cache instead.
    Detect compression type by extension and uncompress.
    Return (rc, buf) where rc is RC_SUCCESS or RC_FAILED,
    and buf is the resulting .rom file contents as bytes.
    """
    tmpdir = "/tmp/msxpi"

    filename = os.path.basename(url)
    cached_path = os.path.join(tmpdir, filename)

    # Download/copy only if not cached
    if not os.path.exists(cached_path):
        if is_local_path(url):
            try:
                os.makedirs(tmpdir, exist_ok=True)
                shutil.copyfile(url, cached_path)
            except Exception as e:
                print(f"Local read failed: {e}")
                return RC_FAILED, f"Local read failed: {e}"
        else:
            try:
                resp = requests.get(url, stream=True, timeout=HTTP_TIMEOUT)
                resp.raise_for_status()
                with open(cached_path, "wb") as f:
                    for chunk in resp.iter_content(chunk_size=8192):
                        f.write(chunk)
            except Exception as e:
                print(f"Download failed: {e}")
                return RC_FAILED, f"Download failed: {e}"
    else:
        print(f"Using cached file: {cached_path}")

    # Handle plain .rom files directly
    ext = filename.lower().split(".")[-1]
    if ext == "rom":
        try:
            with open(cached_path, "rb") as f:
                buf = f.read()
            return RC_SUCCESS, buf
        except Exception as e:
            print(f"Failed to read ROM file: {e}")
            return RC_FAILED, f"Failed to read ROM file: {e}"

    # Otherwise, prepare extraction. Start from an empty extract dir every
    # time: archives may carry read-only files (e.g. 1942.zip), which a plain
    # shutil.rmtree cannot delete on Windows, and any leftover ROM would be
    # picked up instead of the one just extracted.
    extract_dir = os.path.join(tmpdir, "extract")
    try:
        _rmtree_force(extract_dir)
    except Exception as e:
        print(f"Cannot clean extract dir: {e}")
        return RC_FAILED, f"Cannot clean extract dir: {e}"
    os.makedirs(extract_dir, exist_ok=True)
    system = platform.system().lower()

    if ext == "zip":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["unzip", "-o", cached_path, "-d", extract_dir]

    elif ext == "lzh":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["lha", "xq", cached_path]

    elif ext == "pma":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["pma", "x", cached_path]

    elif ext == "arj":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["arj", "x", cached_path, extract_dir]

    else:
        print(f"Unsupported extension: {ext}")
        return RC_FAILED, f"Unsupported extension: {ext}"

    try:
        # Run extraction
        try:
            print(f"Extrating file with command: {cmd}")
            subprocess.run(cmd, cwd=extract_dir, check=True)
        except subprocess.CalledProcessError as e:
            print(f"Extraction failed: {e}")
            return RC_FAILED, f"Extraction failed: {e}"

        # Find the resulting .rom file; prefer one named like the archive
        roms = sorted(os.path.join(root, f)
                      for root, _, files in os.walk(extract_dir)
                      for f in files if f.lower().endswith(".rom"))
        if not roms:
            print("No .rom file found after extraction")
            return RC_FAILED, "No .rom file found after extraction"
        base = os.path.splitext(filename)[0].lower()
        rom_file = next((r for r in roms
                         if os.path.splitext(os.path.basename(r))[0].lower() == base),
                        roms[0])

        # Load into buf
        try:
            with open(rom_file, "rb") as f:
                buf = f.read()
        except Exception as e:
            print(f"Failed to read ROM file: {e}")
            return RC_FAILED, f"Failed to read ROM file: {e}"

        return RC_SUCCESS, buf
    finally:
        # Clean up extracted files, keep cache
        try:
            _rmtree_force(extract_dir)
        except Exception as e:
            print(f"Cannot clean extract dir: {e}")

   
_ploadr_cache = None   # (filepath, rom bytes) of the transfer in progress

def ploadr(parms = None):
    """Fetch a single ROM by filename (resolved against the current MSXPi
    path - same convention as pcopy/pdir/pcd, see cd()'s own basepath =
    getMSXPiVar('PATH')) and send it back using the mapper-aware ROM header
    protocol (see build_rom_header/detect_mapper). This is the direct,
    non-interactive counterpart to msxarchive's browse-and-select flow -
    used by ploadr.com and by EXECROM.MAC's /W option (as "execrom", kept
    as an alias below for backward compatibility), e.g. "ploadr
    zanacex.rom" resolves against whatever path was last set via
    "p cd <path>"."""
    #print(f"ploadr(): {parms}")
    basepath = getMSXPiVar('PATH')
    parts = (parms or '').strip().split()
    filename = parts[0] if parts else ''

    def reject(reason):
        print(reason)
        header = build_rom_header(MAPPER_REJECTED, 0, 0, 0)
        return sendmultiblock(header + reason.encode())

    if not filename:
        return reject("Pi:Error - no filename given")

    # filename arrives already uppercased by MS-DOS's own FCB parsing (the
    # original typed case is gone by the time this command runs, not
    # something this patch can recover) - lowercase it before resolving
    # against a network path, since remote archives conventionally use
    # lowercase filenames and would 404 on a case-sensitive host otherwise.
    # Local filesystem paths are left alone - those may be genuinely
    # case-sensitive in the other direction (a real lowercase-only file
    # living under a path a user typed in whatever case).
    pathType, filepath = pathExpander(filename, basepath)
    if pathType == 1 and filename != filename.lower():
        pathType, filepath = pathExpander(filename.lower(), basepath)

    # Per-block requests reuse the ROM held in memory from this transfer's
    # header request instead of re-fetching/re-extracting it for every
    # 16K block (which ran 7z and wrote the whole extracted ROM to disk
    # once per block). Replaced by the next header/legacy request, dropped
    # after the last block.
    global _ploadr_cache
    is_block_req = len(parts) >= 3
    if is_block_req and _ploadr_cache and _ploadr_cache[0] == filepath:
        buf = _ploadr_cache[1]
        block_index = int(parts[1])
        block_size = int(parts[2])
        offset = block_index * block_size
        chunk = buf[offset:offset + block_size]
        is_last = (offset + len(chunk)) >= len(buf)
        if is_last:
            _ploadr_cache = None
        return sendmultiblock(chunk, header_rc=RC_SUCCESS if is_last else RC_READY)
    _ploadr_cache = None

    rc, buf = fetch_and_uncompress(filepath)
    if rc != RC_SUCCESS:
        reason = buf if isinstance(buf, str) else "Pi:Error - fetch failed"
        return reject(reason)

    if len(buf) <= PLAIN_ROM_MAX_SIZE:
        header = build_rom_header(MAPPER_PLAIN, 0, 0, len(buf))
    else:
        mapper_type, bank_size_kb = detect_mapper(buf)
        if mapper_type is None:
            return reject(f"{filename} ({len(buf)} bytes): unrecognized "
                          f"mapper - not supported yet.")
        if len(buf) > ROM_MAX_SIZE:
            return reject(f"{filename} ({len(buf)} bytes) exceeds the "
                          f"{ROM_MAX_SIZE} byte cap.")
        bank_count = len(buf) // (bank_size_kb * 1024)
        print(f"{filename}: detected mapper type {mapper_type}, "
              f"{bank_size_kb}KB banks, {bank_count} banks")
        header = build_rom_header(mapper_type, bank_size_kb, bank_count, len(buf))

    # Per-block body request: "ploadr <file> <index> <blocksize>" - slices
    # the already-cached buffer and sends exactly one block, then returns,
    # so the dispatch loop is back at "Waiting Command" between every
    # block instead of staying monolithically inside one ploadr() call for
    # the whole transfer. That matters because msxpi-server.py's command
    # dispatch is single-threaded/synchronous (see the main loop) - while
    # ploadr() used to hold the conversation open across the entire body,
    # any real disk access the DOS kernel needed mid-transfer (its DSKCHG
    # contract requires re-validating on disk-related calls) had nowhere
    # correct to land and would desync the wire. Per-block requests close
    # that window entirely, the same way dskiords/dskiosct already do.
    if len(parts) >= 3:
        block_index = int(parts[1])
        block_size = int(parts[2])
        offset = block_index * block_size
        chunk = buf[offset:offset + block_size]
        is_last = (offset + len(chunk)) >= len(buf)
        header_rc = RC_SUCCESS if is_last else RC_READY
        return sendmultiblock(chunk, header_rc=header_rc)

    # Header-only request: "ploadr <file> H" - used by LOADRPI.COM's
    # searchpatch_first, which needs just the header to decide plain-vs-
    # mapped routing and block count before requesting the body above,
    # one block at a time.
    if len(parts) == 2 and parts[1].upper() == 'H':
        _ploadr_cache = (filepath, buf)
        return sendmultiblock(header)

    # Legacy whole-file request: "ploadr <file>" (no extra params) -
    # unchanged, still used by ploadr.c's plain-ROM path.
    rc = sendmultiblock(header)
    if rc != RC_SUCCESS:
        return rc
    rc = sendmultiblock(buf)
    return RC_SUCCESS

# Backward-compatible alias - EXECROM.MAC's /W option and msxarch.c still
# send "execrom <filename>"; the command dispatcher (globals()[cmd.lower()])
# resolves purely by name, so this keeps them working under ploadr()'s
# renamed implementation without needing their own changes.
execrom = ploadr

def msxarchive(parms = None):
    stored_screen = ""  # local variable inside ploadr
    nrows = 22
    ncolumns = 80
    columnwidth = 14
    indexFile = "00index.txt"

    ROM_FILE_EXTENSIONS = (".rom", ".zip", ".lzh", ".pma", ".arj")

    # File size in KB per file name, shown next to each game in the listing.
    # Every source finds sizes its own way (see fetch_file_list); a name with
    # no entry has not been looked up yet, None means the size is unknown.
    sizes = {}

    def _listing_size_kb(text):
        """KB from the size column of an HTTP directory listing: Apache shows
        "128K" / "1.2M", nginx the byte count, Python's http.server nothing."""
        m = re.fullmatch(r"(\d+(?:\.\d+)?)([KMG]?)", text.strip(), re.I)
        if not m:
            return None
        n = float(m.group(1))
        unit = m.group(2).upper()
        if unit == "":
            return math.ceil(n / 1024)
        return math.ceil(n * {"K": 1, "M": 1024, "G": 1024 * 1024}[unit])

    def fetch_file_list(url: str, index: str):
        """Fetch file list from the given URL and return filenames without extensions.
        Skip header (first line) and empty lines."""

        def request_failed(fetch_url, exc):
            if isinstance(exc, requests.exceptions.Timeout):
                detail = "Timed out waiting for the server."
            elif isinstance(exc, requests.exceptions.ConnectionError):
                detail = "Connection refused or server offline."
            elif isinstance(exc, requests.exceptions.TooManyRedirects):
                detail = "Too many redirects."
            else:
                detail = "Network request failed."

            print(f"MSX Archive request failed for {fetch_url}: {exc}")
            return RC_FAILED, (
                "Pi:Error - Cannot open archive URL.\n"
                f"{fetch_url}\n"
                f"{detail}"
            )

        def local_path_failed(path, exc):
            if isinstance(exc, PermissionError):
                detail = "Permission denied."
            elif isinstance(exc, (FileNotFoundError, NotADirectoryError)):
                detail = "File or directory does not exist."
            else:
                detail = "Cannot read this directory."

            print(f"MSX Archive directory failed for {path}: {exc}")
            return RC_FAILED, (
                "Pi:Error - Cannot open archive directory.\n"
                f"{path}\n"
                f"{detail}"
            )

        if is_local_path(url):
            try:
                entries = os.listdir(url)
            except Exception as e:
                return local_path_failed(url, e)
            files = sorted(f for f in entries
                            if f.lower().endswith(ROM_FILE_EXTENSIONS))
            for f in files:
                try:
                    sizes[f] = math.ceil(os.path.getsize(os.path.join(url, f)) / 1024)
                except OSError:
                    sizes[f] = None
            return RC_SUCCESS, files

        CACHE_TTL_SECONDS = 3600

        index_url = url + "/" + index
        cached_file = "/tmp/msxpi/" + index_url.replace(":", "_").replace("/", "+")

        cache_exists = os.path.exists(cached_file)
        cache_expired = cache_exists and (time.time() - os.path.getmtime(cached_file)) > CACHE_TTL_SECONDS

        if not cache_exists or cache_expired:
            print(f"cache expired: {cached_file}" if cache_expired else f"not cached: {cached_file}")
            # Download from the URL
            try:
                response = requests.get(index_url, timeout=HTTP_TIMEOUT)
            except requests.exceptions.RequestException as e:
                return request_failed(index_url, e)

            if response.status_code == 200:
                # Success: parse the content
                lines = response.text.splitlines()
            elif response.status_code == 404:
                # No index file published (e.g. a plain directory server with
                # no 00index.txt, like a local test HTTP server): fall back to
                # the server's own auto-generated directory listing instead.
                print(f"{index} not found, falling back to directory listing at: {url}/")
                try:
                    dir_response = requests.get(url + "/", timeout=HTTP_TIMEOUT)
                except requests.exceptions.RequestException as e:
                    return request_failed(url + "/", e)
                if dir_response.status_code != 200:
                    print(f"Download failed: HTTP {dir_response.status_code} - {dir_response.reason}")
                    files = f"Download failed: HTTP {dir_response.status_code} - {dir_response.reason}"
                    return RC_FAILED,files

                class DirListingParser(HTMLParser):
                    def __init__(self):
                        super().__init__()
                        self.hrefs = []
                    def handle_starttag(self, tag, attrs):
                        if tag == 'a':
                            href = dict(attrs).get('href')
                            if href:
                                self.hrefs.append(href)

                parser = DirListingParser()
                parser.feed(dir_response.text)
                entries = [unquote(h) for h in parser.hrefs if h != '..' and not h.endswith('/')]

                # Servers that show a size print it on the same line, after
                # the link. It is kept as a second column so it survives the
                # cache; the parsing loop below reads the last column.
                listed = {}
                for m in re.finditer(r'<a\s[^>]*href="([^"]+)"[^>]*>.*?</a>([^\n<]*)',
                                     dir_response.text, re.I | re.S):
                    cols = m.group(2).split()
                    kb = _listing_size_kb(cols[-1]) if cols else None
                    if kb is not None:
                        listed[unquote(m.group(1))] = kb
                entries = [f"{e} {listed[e]}" if e in listed else e for e in entries]

                # Prepend a placeholder header line since the parsing loop
                # below always skips line 0 (matches the plain-text index format).
                lines = ["# directory listing"] + entries
            else:
                # Failure: print error message
                print(f"Download failed: HTTP {response.status_code} - {response.reason}")
                files = f"Download failed: HTTP {response.status_code} - {response.reason}"
                return RC_FAILED,files

            # Save to cache for future use
            os.makedirs(os.path.dirname(cached_file), exist_ok=True)
            with open(cached_file, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))

        else:
            # Read from cache
            print(f"Reading from cache: {index_url}")
            with open(cached_file, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()

        files = []
        for i, line in enumerate(lines):
            line = line.strip()
            if i == 0 or not line or line.startswith('#'):  # skip header + empty + comments
                continue
            # Drop extension
            cols = line.split()
            name = cols[0]
            files.append(name)
            # 00index.txt ends each line with the size in KB ("div" for
            # archives of many ROMs); a directory listing line carries it as
            # the second column when the server showed one. Unknown sizes are
            # asked for with HEAD when their page is shown - see size_label.
            if len(cols) > 1 and cols[-1].isdigit():
                sizes[name] = int(cols[-1])
            elif len(cols) > 1:
                sizes[name] = None
        return RC_SUCCESS,files

    def size_label(name):
        """"128K" / "12M", or blank when the size is unknown."""
        kb = sizes.get(name)
        if kb is None:
            return ""
        return f"{kb}K" if kb < 10000 else f"{kb // 1024}M"

    def lookup_sizes(names):
        """HEAD the files whose size no listing gave, only for the page being
        shown - a request per file for a whole archive would take minutes."""
        missing = [n for n in names if n not in sizes]
        if not missing or is_local_path(url):
            return
        from concurrent.futures import ThreadPoolExecutor
        from urllib.parse import urlsplit, urlunsplit

        # On Windows "localhost" tries IPv6 (::1) first and falls back to IPv4
        # after a delay, paid by every request: a page of 25 HEADs to a local
        # IPv4-only http.server took 6 seconds. 127.0.0.1 skips that.
        base = urlsplit(url)
        if base.hostname == "localhost":
            netloc = "127.0.0.1" + (f":{base.port}" if base.port else "")
            base = base._replace(netloc=netloc)
        base = urlunsplit(base).rstrip("/")

        # One session keeps connections open between requests instead of
        # connecting again for every file; pool sized to the worker count.
        session = requests.Session()
        adapter = requests.adapters.HTTPAdapter(pool_connections=1, pool_maxsize=8)
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        def head(name):
            try:
                r = session.head(f"{base}/{name}", timeout=3, allow_redirects=True)
                n = int(r.headers.get("Content-Length", ""))
                return name, math.ceil(n / 1024)
            except Exception:
                return name, None

        with session, ThreadPoolExecutor(max_workers=8) as pool:
            for name, kb in pool.map(head, missing):
                sizes[name] = kb

    def paginate_files(files, rows=nrows, cols=ncolumns, col_width=None):
        """
        Arrange files into pages of rows x cols with horizontal indexing.
        Column width is determined by the longest filename (plus index prefix),
        unless explicitly provided. Pads the last page with spaces so all pages
        have equal size. Ensures a space between columns.
        """
        if not files:
            return []

        # Compute max column width if not provided
        max_index_len = len(str(len(files)))  # e.g. "650" → 3
        if col_width is None:
            max_name_len = max(len(f) for f in files)
            # +1 for the colon, +6 for " 1234K"
            col_width = max_name_len + max_index_len + 1 + SIZE_FIELD

        # At least three columns: the size field would otherwise push a long
        # name like GOODMSX1_0.999.2.ZIP down to two columns. Such names are
        # truncated on screen only; selection still uses the full name.
        col_width = min(col_width, cols // 3 - 1, cols)

        # Ensure at least one column
        cols_count = max(1, cols // (col_width + 1))  # +1 for spacing
        items_per_page = cols_count * rows
        total_pages = max(1, math.ceil(len(files) / items_per_page))

        # Pages hold 0-based file indices, laid out row by row; the text is
        # made in get_page, once the sizes for that page are known.
        pages = []
        for p in range(total_pages):
            start = p * items_per_page
            pages.append((list(range(start, min(start + items_per_page, len(files)))),
                          cols_count, col_width))
        return pages

    SIZE_FIELD = 6  # " 1234K"

    def format_entry(files, i, col_width):
        prefix = f"{i+1}:"
        room = max(1, col_width - len(prefix) - SIZE_FIELD)
        return (prefix + files[i][:room].ljust(room) +
                size_label(files[i]).rjust(SIZE_FIELD))

    def get_page(files, pages, page_number, width=ncolumns):
        """
        Return only the requested page as plain text, update stored_screen.
        Each line is padded with spaces to 'width' and concatenated without newlines.
        """
        nonlocal stored_screen  # use nonlocal to modify outer variable
        total_pages = len(pages)
        lines = []
        if 1 <= page_number <= total_pages:
            indices, cols_count, col_width = pages[page_number - 1]
            lookup_sizes([files[i] for i in indices])
            entries = [format_entry(files, i, col_width) for i in indices]
            for r in range(nrows):
                row = entries[r * cols_count:(r + 1) * cols_count]
                # Add one space after each column, trim to exactly 'width'
                lines.append("".join(e.ljust(col_width) + " " for e in row)[:width])
    
        # Pad each line to the full width with spaces
        padded_lines = [line.ljust(width) for line in lines]
    
        # Concatenate into one continuous string (no '\n')
        stored_screen = "".join(padded_lines)
        return stored_screen

    def get_total_files(files):
        """Return the total number of files."""
        return len(files)
    
    def get_total_pages(pages):
        """Return the total number of pages."""
        return len(pages)
    
    def get_fileName(files, index):
        """
        Return the filename at the given 1-based index.
        If the index is out of range, return None.
        """
        if 1 <= index <= len(files):
            return files[index - 1]   # convert from 1-based to 0-based
        else:
            return None

    # This command requires parameter
    rc, url = readParameters("This command requires a parameter", True)
    if rc == RC_FAILED:
        return RC_FAILED

    PAGESIZE = nrows * ncolumns

    print(f"Fetching MSX Archive file list from: {url + '/'  + indexFile}")    
    rc, files = fetch_file_list(url, indexFile)

    if rc == RC_FAILED:
        senddata(RC_FAILED, files.encode().ljust(PAGESIZE, b'\x00'))
        return RC_FAILED

    pages = paginate_files(files, nrows, ncolumns, None)

    print(f"total files = {get_total_files(files)}, total pages = {get_total_pages(pages)}")
    #text = get_page(files, pages, 1)
    #print(text)
    #print("")

    page = 1
    current_page = 1
    global DISABLETIMEOUT
    DISABLETIMEOUT = True # Disable transfers timeout for MSX Archive browsing
    cmd = "1"
    text = get_page(files, pages, page, ncolumns)
    rc = sendmultiblock(text.encode().ljust(PAGESIZE, b'\x00'))

    try:
        while True:
            rc, parm = recvdata2();
            parm = parm.decode(errors="ignore").split("\x00", 1)[0]
            cmd = str(parm).lower()  # normalize to string for command checks

            if cmd == "n" or cmd == "N":
                # go to next page
                page = int(current_page) + 1
                if page > get_total_pages(pages):
                    page = 1
    
                current_page = page
                text = get_page(files, pages, page, ncolumns)

            elif cmd == "p" or cmd == "P":
                # go to previous page
                page = int(current_page) - 1
                if page < 1:
                    page = get_total_pages(pages)
                current_page = page
                text = get_page(files, pages, page, ncolumns)

            elif cmd == "q" or cmd == "Q":
                break
            else:
                # Every outcome of a numeric selection (load, or reject with a
                # reason) ends the archive session, so each one always sends the
                # 16-byte ROM header first - the client now unconditionally
                # expects it right after sending a file number. Rejections carry
                # MAPPER_REJECTED plus a short reason string instead of a ROM body,
                # so the client never mistakes a plain-text reply for ROM data.
                def reject(reason):
                    print(reason)
                    header = build_rom_header(MAPPER_REJECTED, 0, 0, 0)
                    sendmultiblock(header + reason.encode())
                    return RC_FAILED

                # The MSX appends the addresses it relocated its resident
                # bank-switch handlers to, so this side can patch the image and
                # the MSX does not have to scan it. Absent => old client, which
                # patches for itself.
                msx_handlers = None
                try:
                    fields = str(parm).split()
                    file_num = int(fields[0])
                    if len(fields) >= 7:
                        msx_handlers = tuple(int(f, 16) for f in fields[1:8])
                except (ValueError, TypeError, IndexError):
                    return reject(f"Invalid input: {cmd}")

                if file_num < 1 or file_num > get_total_files(files):
                    return reject(f"File {file_num} does not exist.")

                filename = get_fileName(files, file_num)
                print(f"Selected file: {filename}")
                filepath = os.path.join(url, filename) if is_local_path(url) else f"{url}/{filename}"
                rc, buf = fetch_and_uncompress(filepath)
                if rc != RC_SUCCESS:
                    return reject(buf)

                # openMSX's softwaredb.xml decides how the ROM is loaded;
                # detect_mapper() is only the fallback for unlisted ROMs.
                dbinfo = romdb_lookup(buf, get_romdb())
                if dbinfo:
                    # ASCII only: titles such as "Akumajō Dracula" raised
                    # UnicodeEncodeError on a cp1252 Windows console, which
                    # aborted the load and left the MSX without a ROM header.
                    title = dbinfo[3].encode("ascii", "replace").decode("ascii")
                    print(f"{filename}: ROM database: {dbinfo[2]} ({title})")
                    if dbinfo[0] == "unsupported":
                        return reject(f"{filename}: {dbinfo[2]} mapper is not "
                                      f"supported.")
                plain = (dbinfo[0] == "plain") if dbinfo else \
                    len(buf) <= PLAIN_ROM_MAX_SIZE
                if plain and len(buf) > PLAIN_ROM_MAX_SIZE:
                    return reject(f"{filename} ({len(buf)} bytes): plain ROM "
                                  f"larger than {PLAIN_ROM_MAX_SIZE} bytes.")
                if plain:
                    # The MSX runs the image from RAM, where stores into the
                    # ROM window succeed instead of being discarded - see
                    # neutralise_rom_writes in mapper_detect.py.
                    # A 16KB cartridge that decodes only 14 address bits appears
                    # at 4000h AND 8000h, and may be built to run from 8000h:
                    # ICEWORLD.ROM ("Mirrored" in softwaredb.xml) has INIT
                    # 8010h, which pointed into empty RAM when only 4000h was
                    # loaded. Its code is traced from 8000h, and the image is
                    # sent twice to fill both pages.
                    init = buf[2] | (buf[3] << 8) if len(buf) >= 4 else 0
                    page2 = len(buf) == 0x4000 and 0x8000 <= init < 0xC000
                    buf, nstore = neutralise_rom_writes(buf, 0x8000 if page2 else 0x4000)
                    print(f"{filename}: neutralised {nstore} stores into ROM")
                    if page2:
                        buf = buf + buf
                    # An 8KB cartridge decodes only 13 address bits, so the
                    # image also appears at 6000h; FROGGER.ROM jumps there and
                    # showed a black screen when only 4000h was loaded.
                    if len(buf) == 0x2000:
                        buf = buf + buf
                    header = build_rom_header(MAPPER_PLAIN, 0, 0, len(buf))
                else:
                    if dbinfo:
                        mapper_type, bank_size_kb = dbinfo[1]
                    else:
                        mapper_type, bank_size_kb = detect_mapper(buf)
                        print(f"{filename}: not in the ROM database - "
                              f"detected mapper type {mapper_type}")
                    if mapper_type is not None and msx_handlers:
                        buf, npatch = patch_for_msx(buf, mapper_type, msx_handlers)
                        print(f"{filename}: patched {npatch} bank-switch sites "
                              f"server-side")
                    if mapper_type is None:
                        return reject(f"{filename} ({len(buf)} bytes): unrecognized "
                                      f"mapper - not supported yet.")
                    if len(buf) > ROM_MAX_SIZE:
                        return reject(f"{filename} ({len(buf)} bytes) exceeds the "
                                      f"{ROM_MAX_SIZE} byte cap.")
                    bank_count = len(buf) // (bank_size_kb * 1024)
                    print(f"{filename}: detected mapper type {mapper_type}, "
                          f"{bank_size_kb}KB banks, {bank_count} banks")
                    header = build_rom_header(mapper_type, bank_size_kb, bank_count, len(buf))

                # The file name follows the header so the MSX can show what
                # it is loading; a client that does not use it ignores it,
                # like the reason text of a rejection.
                name = filename.encode("ascii", "replace")[:64]
                rc = sendmultiblock(header + name)
                if rc != RC_SUCCESS:
                    return rc
                rc = sendmultiblock(buf)
                return RC_SUCCESS

            rc = senddata(RC_SUCCESS, text.encode().ljust(PAGESIZE, b'\x00'))
            #print(text)

    finally:
        DISABLETIMEOUT = False # Restore timeout setting

def ShowSecurityDisclaimer(parms = None):
    print("\n=====================================================================================")
    print("This server process is meant to handle communication with a MSX computer.")
    print("It allows the MSX to:\n")
    print(" * List/read (any) file from this computer or network (via the the PDIR/PCOPY commands).\n")
    print(" * Execute arbitrary(!) shell commands (via the PRUN command).\n")
    if hostType == "RaspberryPi":
        print(" * Configure the WiFi settings (via the PSET/PWIFI commands).\n")
    print("Some very few commands designed specifically for Raspberry Pi requires elevation of")
    print("privileges using sudo - these commands will not be executed in the PC platforms and")
    print("when possible, a message will be returned to the MSX informing that the command is")
    print("not supported.")
    print("However notice that using PRUN, the MSX user can execute any commands in the host,")
    print("bypassing the controls in the native MSXPi commands.")
    print("=======================================================================================\n")   

def template(parms = None):

    # This method is a template for new commands
    # 
    #print("template()")

    # If your MSX command send parameters, we go read them:
    if parms == None or parms == "":
        print(f"Sending error message")
        rc = sendmultiblock("This command requires a parameter".encode())
        return

    response = f"Response from MSXPi: I received parameter '{parms}'"
    print(f"Sending back: {response}")
    rc = sendmultiblock(response.encode())
    
    return

def irc(parms):
    #print(f"irc():{parms!r}")

    global ircsock

    # ------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------
    def sendmsg(text: str, rc=RC_SUCCESS):
        #print(f"[irc] sendmsg: text={text!r}, rc={rc}")
        sendmultiblock(text.encode(), rc)

    def not_connected():
        #print("[irc] not_connected()")
        sendmsg("Pi:Er:Not connected", RC_SUCCNOSTD)
        return RC_SUCCNOSTD

    # ------------------------------------------------------------
    # Decode command
    # ------------------------------------------------------------
    if not parms:
        cmd = ""
    else:
        if isinstance(parms, (bytes, bytearray)):
            cmd = parms.decode(errors="ignore").strip().lower()
        else:
            cmd = str(parms).strip().lower()

    ircserver = getMSXPiVar("IRCADDR")
    ircport   = int(getMSXPiVar("IRCPORT"))
    msxnick   = getMSXPiVar("IRCNICK")

    #print(f"[irc] cmd='{cmd}', server={ircserver}, port={ircport}, nick={msxnick}")

    try:
        # ------------------------------------------------------------
        # CONNECT
        # ------------------------------------------------------------
        if cmd.lower().startswith("conn"):
            print("[irc] CONNECT")
            parts = cmd.split()
            jnick = parts[1] if len(parts) > 1 else msxnick
            if jnick == "none":
                jnick = msxnick
            #print(f"[irc] connect nick={jnick}")

            # Close previous
            if ircsock is not None:
                #print("[irc] closing previous socket")
                try:
                    ircsock.close()
                except Exception as e:
                    print(f"[irc] error closing previous socket: {e}")

            try:
                #print(f"[irc] creating socket to {(ircserver, ircport)}")
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.connect((ircserver, ircport))
                #print("[irc] socket connected")
            except Exception as e:
                print(f"[irc] connect exception: {e}")
                ircsock = None
                sendmsg("Pi:Er:Connect error: " + str(e), RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            ircsock = s
            ircsock.setblocking(False)
            #print("[irc] socket set to non-blocking")

            user_line = f"USER {jnick} 0 * :{jnick}\r\n"
            nick_line = f"NICK {jnick}\r\n"
            #print(f"[irc] >> {user_line!r}")
            ircsock.send(user_line.encode())
            #print(f"[irc] >> {nick_line!r}")
            ircsock.send(nick_line.encode())

            sendmsg("Pi:Ok:Connected to " + ircserver, RC_SUCCNOSTD)
            return RC_SUCCNOSTD
      
        # ------------------------------------------------------------
        # SEND MESSAGE
        # ------------------------------------------------------------
        elif cmd.startswith("say"):
            print("[irc] MSG")
            if ircsock is None:
                return not_connected()
        
            raw = parms[4:].strip()
            #print(f"[irc] msg raw='{raw}'")
            
            parts = raw.split(maxsplit=1)
            if len(parts) == 2:
                target, text = parts
            else:
                sendmsg("Pi:Er:Bad format", RC_SUCCNOSTD)
                return RC_SUCCNOSTD
            
            # Detect /names
            if text.lower().startswith("/names"):
                print("[irc] /names")
                try:
                    line = f"NAMES {target}\r\n"
                    print(f"[irc] >> {line!r}")
                    ircsock.send(line.encode())
                except Exception as e:
                    print(f"[irc] NAMES send exception: {e}")
                    sendmsg("Pi:Er:NAMES error: " + str(e), RC_SUCCNOSTD)
                    return RC_SUCCNOSTD
            
                sendmsg("Pi:Ok:NAMES sent", RC_SUCCNOSTD)
                return RC_SUCCNOSTD
        
            # Normal SAY → PRIVMSG
            try:
                line = f"PRIVMSG {raw}\r\n"
                #print(f"[irc] >> {line!r}")
                ircsock.send(line.encode())
            except Exception as e:
                print(f"[irc] send exception: {e}")
                sendmsg("Pi:Er:Send error: " + str(e), RC_SUCCNOSTD)
                return RC_SUCCNOSTD
        
            #sendmsg("Pi:Ok:Sent", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

        # ------------------------------------------------------------
        # JOIN
        # ------------------------------------------------------------
        elif cmd.lower().startswith("join"):
            print("[irc] JOIN")
            if ircsock is None:
                #print("[irc] JOIN but ircsock is None")
                return not_connected()

            parts = cmd.split()
            #print(f"[irc] join parts={parts}")
            if len(parts) < 2:
                sendmsg("Pi:Er:Missing channel", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            chan = parts[1]
            try:
                line = f"JOIN {chan}\r\n"
                #print(f"[irc] >> {line!r}")
                ircsock.send(line.encode())
            except Exception as e:
                print(f"[irc] join exception: {e}")
                sendmsg("Pi:Er:Join error: " + str(e), RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            sendmsg("Pi:Ok:Joined", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

        # ------------------------------------------------------------
        # READ
        # ------------------------------------------------------------
        elif cmd.lower().startswith("read"):
            print("[irc] READ")
            if ircsock is None:
                #print("[irc] READ but ircsock is None")
                sendmsg("Pi:Er:Not connected", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            try:
                data = ircsock.recv(2048)
                #print(f"[irc] recv raw={data!r}")
            except BlockingIOError:
                #print("[irc] recv BlockingIOError (no data yet)")
                sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                return RC_SUCCNOSTD
            except Exception as e:
                print(f"[irc] recv exception: {e}")
                sendmsg("Pi:Er:Read error: " + str(e), RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            if not data:
                #print("[irc] recv: empty data (connection closed?)")
                sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            raw = data.decode(errors="ignore")
            #print(f"[irc] decoded raw={raw!r}")
            if not raw.strip():
                #print("[irc] decoded raw is only whitespace")
                sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            lines = raw.replace("\r", "").split("\n")
            #print(f"{lines!r}")
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                print(f"[irc] line='{line}'")

                # PING
                if line.startswith("PING :"):
                    token = line[6:]
                    print(f"[irc] PING detected, token={token!r}")
                    try:
                        pong = f"PONG :{token}\r\n"
                        #print(f"[irc] >> {pong!r}")
                        ircsock.send(pong.encode())
                    except Exception as e:
                        print(f"[irc] PONG send exception: {e}")
                    sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                    return RC_SUCCNOSTD

                # NAMES reply (353)
                if " 353 " in line:
                    print("[irc] NAMES list detected")
                    # Example: :server 353 msxpi = #openmsx :nick1 nick2 nick3
                    try:
                        parts = line.split(" :", 1)
                        if len(parts) == 2:
                            users = parts[1]
                            sendmsg("Pi:Ok:Users " + users, RC_SUCCESS)
                            print(f"[irc] NAMES parsed: users={users!r}")
                            return RC_SUCCESS
                    except Exception as e:
                        print(f"[irc] NAMES parse exception: {e}")
                        sendmsg("Pi:Ok:Users", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                # End of NAMES list (366) - housekeeping marker only, no
                # content for the user to see, so RC_SUCCNOSTD like the
                # other "nothing interesting" acks (e.g. "NAMES sent")
                if " 366 " in line:
                    #print("[irc] End of NAMES list")
                    sendmsg("Pi:Ok:EndUsers", RC_SUCCNOSTD)
                    return RC_SUCCNOSTD

                # JOIN reply from server
                if " JOIN " in line:
                    print("[irc] JOIN")
                    try:
                        # Example: :msxpi!~msxpi@host JOIN #openmsx
                        # With extended-join capability, the server can
                        # append more fields after the channel (account
                        # name, then :realname) - take only the first
                        # whitespace-delimited token so those don't leak
                        # into the channel name shown to the user.
                        prefix, rest = line[1:].split(" ", 1)
                        nick = prefix.split("!", 1)[0]
                        chan = rest.split("JOIN", 1)[1].strip().split(" ", 1)[0]
                        #print(f"[irc] JOIN parsed: nick={nick!r}, chan={chan!r}")
                    except Exception as e:
                        print(f"[irc] JOIN parse exception: {e}")
                        sendmsg("Pi:Ok:Joined", RC_SUCCESS)
                        return RC_SUCCESS

                    # If it's our own JOIN
                    if nick.lower() == msxnick.lower():
                        sendmsg(f"Pi:Ok:Joined {chan}", RC_SUCCESS)
                        return RC_SUCCESS

                    # Someone else joined the channel
                    sendmsg(f"Pi:Ok:{nick} joined {chan}", RC_SUCCESS)
                    return RC_SUCCESS

                # Registration complete (end of MOTD)
                if "End of message of the day" in line:
                    #print("[irc] Registration complete — ready to JOIN")
                    irc_registered = True
                    sendmsg("Pi:Ok:Ready", RC_SUCCNOSTD)
                    return RC_SUCCNOSTD

                # PRIVMSG
                if " PRIVMSG " in line:
                    print("[irc] PRIVMSG")
                    try:
                        prefix, rest = line[1:].split(" ", 1)
                        nick = prefix.split("!", 1)[0]
                        #print(f"[irc] prefix={prefix!r}, nick={nick!r}, rest={rest!r}")
                    except Exception as e:
                        #print(f"[irc] PRIVMSG parse prefix exception: {e}")
                        sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                    if " :" not in rest:
                        #print("[irc] PRIVMSG rest has no ' :' separator")
                        sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                    before, text = rest.split(" :", 1)
                    parts = before.split()
                    #print(f"[irc] before={before!r}, text={text!r}, parts={parts!r}")
                    if len(parts) < 2 or parts[0].upper() != "PRIVMSG":
                        #print("[irc] PRIVMSG parts invalid")
                        sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                    target = parts[1]
                    if msxnick in target:
                        target = "private"

                    # CTCP requests (VERSION, PING, TIME, CLIENTINFO, etc.)
                    # are wrapped in \x01...\x01 - these are automated
                    # client-fingerprinting probes from bots/clients, not
                    # real chat content, so don't surface them. CTCP ACTION
                    # (/me) is real content though - unwrap and show that.
                    if text.startswith("\x01"):
                        ctcp = text.strip("\x01")
                        if ctcp.upper().startswith("ACTION "):
                            text = "* " + nick + " " + ctcp[7:]
                            sendmsg("Pi:Ok:<" + target + "> " + text, RC_SUCCESS)
                            return RC_SUCCESS
                        #print(f"[irc] CTCP request from {nick} ignored: {ctcp!r}")
                        sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                    formatted = f"<{target}> {nick} -> {text}"
                    #print(f"[irc] formatted message={formatted!r}")
                    sendmsg("Pi:Ok:" + formatted, RC_SUCCESS)
                    return RC_SUCCESS

            #print("[irc] no meaningful lines found")
            sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

        # ------------------------------------------------------------
        # QUIT
        # ------------------------------------------------------------
        elif cmd.lower().startswith("quit") or cmd.lower().startswith("part"):
            print("[irc] QUIT/PART")
            if ircsock is not None:
                try:
                    #print("[irc] >> b'QUIT\\r\\n'")
                    ircsock.send(b"QUIT\r\n")
                    ircsock.close()
                    #print("[irc] socket closed")
                except Exception as e:
                    print(f"[irc] quit/close exception: {e}")
                ircsock = None

            sendmsg("Pi:leaving room", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

        # ------------------------------------------------------------
        # UNKNOWN
        # ------------------------------------------------------------
        else:
            print(f"[irc] UNKNOWN command: {cmd!r}")
            sendmsg("Pi:No valid command received", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

    except Exception as e:
        print("[irc] Caught top-level exception:", e)
        sendmsg("Pi:" + str(e), RC_SUCCNOSTD)
        return RC_SUCCNOSTD

# -----------------------------
# API keys
# -----------------------------
# From msxpi.ini, like OPENAIKEY - never in this file. These were hardcoded
# here until v1.6, which put four live keys in a public repository; they have
# been revoked, and the replacements live on the Pi in
# /home/pi/msxpi/msxpi.ini, which is not in the repository. target/msxpi.ini
# lists the names with empty values.
#
# Read per call rather than once at import: `p set FINNHUBKEY ...` rewrites the
# file and updates psetvar, and a key set that way has to take effect without
# restarting the server.
def _api_key(name):
    return getMSXPiVar(name).strip()


RAPIDAPI_HOST_DEFAULT = "apidojo-yahoo-finance-v1.p.rapidapi.com"

DEFAULT_COOLDOWN = 60  # seconds
# Yahoo cooldown state
yahoo_cooldown_until = 0

def norm(sym):
    return sym.replace("-", "").upper()

# -----------------------------
# Provider base class
# -----------------------------
class QuoteProvider:
    name = "BASE"
    def fetch_batch(self, symbols):
        raise NotImplementedError

# -----------------------------
# Yahoo Provider
# -----------------------------
class YahooProvider(QuoteProvider):
    name = "Yahoo"
    def fetch_batch(self, symbols):
        url = f"https://{RAPIDAPI_HOST}/market/v2/get-quotes"
        params = {"region": "US", "symbols": ",".join(symbols)}
        headers = {"X-RapidAPI-Key": _api_key("RAPIDAPIKEY"),
                   "X-RapidAPI-Host": _api_key("RAPIDAPIHOST") or RAPIDAPI_HOST_DEFAULT}

        r = requests.get(url, headers=headers, params=params, timeout=10)
        r.raise_for_status()
        data = r.json()
        results = data.get("quoteResponse", {}).get("result", [])

        out = {}
        for item in results:
            sym = item.get("symbol")
            if sym:
                out[sym.upper()] = item
        return out

# -----------------------------
# Finnhub Provider
# -----------------------------
class FinnhubProvider(QuoteProvider):
    name = "Finnhub"
    def fetch_batch(self, symbols):
        out = {}
        for s in symbols:
            url = "https://finnhub.io/api/v1/quote"
            params = {"symbol": s, "token": _api_key("FINNHUBKEY")}
            r = requests.get(url, params=params, timeout=10)
            r.raise_for_status()
            q = r.json()
            out[s] = {
                "symbol": s,
                "regularMarketPrice": q.get("c", 0),
                "regularMarketChange": q.get("d", 0),
                "regularMarketVolume": int(q.get("v", 0))
            }
        return out
    def fetch_history(self, symbol, interval="1", range_="1d"):
        # interval: 1,5,15,30,60
        # range_: "1d","5d","1mo","3mo","6mo","1y"
        resolution = interval.replace("min", "")

        now = int(time.time())
        if range_ == "1d": start = now - 86400
        elif range_ == "5d": start = now - 5*86400
        elif range_ == "1mo": start = now - 30*86400
        else: start = now - 365*86400

        url = "https://finnhub.io/api/v1/stock/candle"
        params = {
            "symbol": symbol,
            "resolution": resolution,
            "from": start,
            "to": now,
            "token": _api_key("FINNHUBKEY")
        }

        r = requests.get(url, params=params, timeout=HTTP_TIMEOUT)
        data = r.json()

        if data.get("s") != "ok":
            return []

        candles = []
        for i in range(len(data["t"])):
            candles.append({
                "time": data["t"][i],
                "open": data["o"][i],
                "high": data["h"][i],
                "low": data["l"][i],
                "close": data["c"][i],
                "volume": data["v"][i]
            })

        return candles

# -----------------------------
# TwelveData Provider
# -----------------------------
def normalize_for_twelvedata(symbol):
    if "-USD" in symbol:
        return symbol.replace("-", "/")
    return symbol

class TwelveDataProvider(QuoteProvider):
    name = "TwelveData"
    def fetch_batch(self, symbols):
        # Convert BTC-USD → BTC/USD
        td_symbols = [normalize_for_twelvedata(s) for s in symbols]

        url = "https://api.twelvedata.com/quote"
        params = {"symbol": ",".join(td_symbols), "apikey": _api_key("TWELVEDATAKEY")}
        r = requests.get(url, params=params, timeout=10)
        r.raise_for_status()
        data = r.json()

        out = {}
        for s, td_s in zip(symbols, td_symbols):
            q = data.get(td_s)
            if not q:
                continue
            out[s] = {
                "symbol": s,
                "regularMarketPrice": float(q["close"]),
                "regularMarketChange": float(q["change"]),
                "regularMarketVolume": int(q.get("volume", 0))
            }
        return out

class CoinGeckoProvider(QuoteProvider):
    name = "CoinGecko"

    id_map = {
        "BTC-USD": "bitcoin",
        "XRP-USD": "ripple",
        "CRO-USD": "crypto-com-chain",
    }

    def fetch_batch(self, symbols):
        # Filter only symbols CoinGecko supports
        ids = []
        sym_map = {}

        for s in symbols:
            cid = self.id_map.get(s.upper())
            if cid:
                ids.append(cid)
                sym_map[cid] = s.upper()

        if not ids:
            return {}

        url = "https://api.coingecko.com/api/v3/simple/price"
        params = {
            "ids": ",".join(ids),
            "vs_currencies": "usd",
            "include_24hr_vol": "true"
        }

        try:
            r = requests.get(url, params=params, timeout=10)
            r.raise_for_status()
            data = r.json()
        except Exception as e:
            print(f"[PROVIDER] CoinGecko batch failed: {e}")
            cooldown_provider("CoinGecko", 60)
            return {}

        out = {}
        for cid, sym in sym_map.items():
            if cid in data:
                q = data[cid]
                out[sym] = {
                    "symbol": sym,
                    "regularMarketPrice": float(q["usd"]),
                    "regularMarketVolume": float(q.get("usd_24h_vol", 0)),
                    "regularMarketOpen": 0,
                    "regularMarketDayHigh": 0,
                    "regularMarketDayLow": 0,
                    "regularMarketPreviousClose": 0,
                }

        return out

    def fetch_history(self, symbol, interval="1m", range_="1d"):
        coin = symbol.split("-")[0].lower()

        url = f"https://api.coingecko.com/api/v3/coins/{coin}/market_chart"
        params = {
            "vs_currency": "usd",
            "days": "1" if range_=="1d" else "7"
        }

        r = requests.get(url, params=params, timeout=HTTP_TIMEOUT)
        data = r.json()

        candles = []
        for ts, price in data["prices"]:
            candles.append({
                "time": ts,
                "open": price,
                "high": price,
                "low": price,
                "close": price,
                "volume": 0
            })

        return candles

class StooqProvider(QuoteProvider):
    name = "Stooq"

    def fetch_history(self, symbol, interval="1d", range_="1mo"):
        # Stooq only supports daily data
        url = f"https://stooq.com/q/d/l/?s={symbol.lower()}&i=d"

        r = requests.get(url, timeout=HTTP_TIMEOUT)
        if r.status_code != 200:
            return []

        lines = r.text.strip().split("\n")
        if len(lines) < 2:
            return []

        candles = []
        for line in lines[1:]:
            date, o, h, l, c, v = line.split(",")
            candles.append({
                "time": date,
                "open": float(o),
                "high": float(h),
                "low": float(l),
                "close": float(c),
                "volume": int(v) if v.isdigit() else 0
            })

        return candles

    def convert_symbol(self, s):
        s = s.upper()
        if s.endswith(".L"):
            return s.replace(".L", ".UK")
        return None  # Stooq only used for LSE here

    def fetch_batch(self, symbols):
        out = {}

        for s in symbols:
            stooq_sym = self.convert_symbol(s)
            if not stooq_sym:
                continue

            url = f"https://stooq.com/q/l/?s={stooq_sym}&f=ohlcv"
            try:
                r = requests.get(url, timeout=10)
                r.raise_for_status()
                text = r.text.strip()

                # Format: SYMBOL,OPEN,HIGH,LOW,CLOSE,VOLUME
                parts = text.split(',')
                if len(parts) < 6:
                    continue

                _, o, h, l, c, v = parts

                out[s.upper()] = {
                    "symbol": s.upper(),
                    "regularMarketPrice": float(c),
                    "regularMarketOpen": float(o),
                    "regularMarketDayHigh": float(h),
                    "regularMarketDayLow": float(l),
                    "regularMarketPreviousClose": float(c),
                    "regularMarketVolume": int(float(v)),
                }

            except Exception as e:
                print(f"[Stooq] Failed for {s}: {e}")
                continue

        return out

class AlphaVantageProvider(QuoteProvider):
    name = "AlphaVantage"

    def convert_symbol(self, s):
        s = s.upper()
        if s.endswith(".L"):
            return s.replace(".L", ".LON")
        return s  # US stocks are fine

    def fetch_batch(self, symbols):
        out = {}

        for s in symbols:
            av_sym = self.convert_symbol(s)

            url = "https://www.alphavantage.co/query"
            params = {
                "function": "GLOBAL_QUOTE",
                "symbol": av_sym,
                "apikey": _api_key("ALPHAVANTAGEKEY")
            }

            try:
                r = requests.get(url, params=params, timeout=10)
                r.raise_for_status()
                data = r.json().get("Global Quote", {})

                if not data:
                    continue

                out[s.upper()] = {
                    "symbol": s.upper(),
                    "regularMarketPrice": float(data.get("05. price", 0)),
                    "regularMarketOpen": float(data.get("02. open", 0)),
                    "regularMarketDayHigh": float(data.get("03. high", 0)),
                    "regularMarketDayLow": float(data.get("04. low", 0)),
                    "regularMarketPreviousClose": float(data.get("08. previous close", 0)),
                    "regularMarketVolume": int(float(data.get("06. volume", 0))),
                }

            except Exception as e:
                print(f"[AlphaVantage] Failed for {s}: {e}")
                continue

        return out

    def fetch_history(self, symbol, interval="1min", range_="1d"):
        url = "https://www.alphavantage.co/query"
        params = {
            "function": "TIME_SERIES_INTRADAY",
            "symbol": symbol,
            "interval": interval,
            "apikey": _api_key("ALPHAVANTAGEKEY"),
            "outputsize": "compact" if range_ == "1d" else "full"
        }

        r = requests.get(url, params=params, timeout=HTTP_TIMEOUT)
        data = r.json()

        key = f"Time Series ({interval})"
        if key not in data:
            return []

        candles = []
        for ts, values in data[key].items():
            candles.append({
                "time": ts,
                "open": float(values["1. open"]),
                "high": float(values["2. high"]),
                "low": float(values["3. low"]),
                "close": float(values["4. close"]),
                "volume": int(values["5. volume"])
            })

        candles.reverse()  # chronological order
        return candles

# -----------------------------
# Determine symbol type
# -----------------------------
def get_symbol_type(symbol):
    if "-USD" in symbol:
        return "crypto"
    elif ".L" in symbol:
        return "uk_stock"
    else:
        return "us_stock"

# -----------------------------
# Provider priority per symbol type
# -----------------------------
symbol_provider_map = {
    "crypto": [TwelveDataProvider, YahooProvider, FinnhubProvider],
    "uk_stock": [YahooProvider, TwelveDataProvider, FinnhubProvider],
    "us_stock": [FinnhubProvider, YahooProvider, TwelveDataProvider],
}
provider_cooldowns = {
    "Yahoo": 0,
    "Finnhub": 0,
    "TwelveData": 0,
    "CoinGecko": 0,
    "Stooq": 0,
    "AlphaVantage": 0,
}

def provider_available(name):
    return time.time() >= provider_cooldowns[name]

def cooldown_provider(name, seconds=DEFAULT_COOLDOWN):
    provider_cooldowns[name] = time.time() + seconds
    print(f"[COOLDOWN] {name} disabled for {seconds}s")

def is_yahoo_available():
    return time.time() >= yahoo_cooldown_until

def mark_yahoo_rate_limited():
    global yahoo_cooldown_until
    yahoo_cooldown_until = time.time() + 60   # 60-second cooldown

def choose_providers(symbol):
    if "-USD" in symbol:  # crypto
        return [CoinGeckoProvider, YahooProvider]

    if ".L" in symbol:  # LSE stocks
        return [YahooProvider, StooqProvider, AlphaVantageProvider]

    # US stocks
    return [YahooProvider, FinnhubProvider, AlphaVantageProvider]

# -----------------------------
# Progressive batch fetch with failover
# -----------------------------
def fetch_batch(symbols):
    global yahoo_cooldown_until

    results = {}
    pending = list(symbols)

    # Split into chunks of 8 to avoid Yahoo throttling
    chunks = [pending[i:i+8] for i in range(0, len(pending), 8)]

    for chunk in chunks:
        for sym in chunk:
            providers = choose_providers(sym)

            for provider_cls in providers:
                # Skip Yahoo if in cooldown
                if provider_cls is YahooProvider and not is_yahoo_available():
                    continue

                p = provider_cls()
                try:
                    data = p.fetch_batch([sym])
                    if data:
                        results.update(data)
                        # Save last known good data
                        for k, v in data.items():
                            nk = norm(k)
                            v["_fallback"] = False
                            last_good[nk] = v
                            results[nk] = v

                        break  # success for this symbol

                except requests.exceptions.HTTPError as e:
                    if provider_cls is YahooProvider and e.response.status_code == 429:
                        print("[YAHOO] Rate limited, entering cooldown")
                        mark_yahoo_rate_limited()
                        continue
                    else:
                        print(f"[PROVIDER] {p.name} failed for {sym}: {e}")
                        continue

                except Exception as e:
                    print(f"[PROVIDER] {p.name} error for {sym}: {e}")
                    continue

    # Report failures
    missing = [s for s in symbols if norm(s) not in results]

    for sym in missing:
        key = norm(sym)
        if key in last_good:
            fallback = last_good[key].copy()
            fallback["_fallback"] = True
            results[key] = fallback
            print(f"[FALLBACK] Using last known data for {sym}")
        else:
            print(f"[FAIL] No data and no fallback for {sym}")

    return results

# -----------------------------
# Global cache state
# -----------------------------
cache = {}
last_good = {}
cache_timestamp = 0
cache_symbols = []
cache_lock = threading.Lock()

cache_thread = None
cache_running = False
cache_interval = 60

# -----------------------------
# Background cache updater
# -----------------------------
def cache_updater():
    global cache, cache_timestamp, cache_running
    print(f"[CACHE] updater started interval={cache_interval}")

    while cache_running:
        try:
            if cache_symbols:
                # Check if ANY provider is available
                any_available = any(provider_available(p) for p in provider_cooldowns)

                if not any_available:
                    print("[CACHE] All providers cooling down, skipping this cycle")
                else:
                    data = fetch_batch(cache_symbols)
                    with cache_lock:
                        cache = data
                        cache_timestamp = time.time()
                    print(f"[CACHE] refreshed {len(data)} symbols")

        except Exception as e:
            print("[CACHE] error:", e)

        time.sleep(cache_interval)

    print("[CACHE] stopped")

def build_non_temporal_candles(candles, threshold):
    """
    Convert historical OHLC candles into non-temporal candles.
    threshold = price movement required to start a new candle
    """
    if not candles:
        return []

    nt = []  # final non-temporal candles

    # Start first candle
    active = {
        "open": candles[0]["open"],
        "high": candles[0]["open"],
        "low":  candles[0]["open"],
        "close": candles[0]["open"],
        "volume": 0
    }

    for c in candles:
        price = c["close"]

        # Update active candle
        active["high"] = max(active["high"], price)
        active["low"]  = min(active["low"], price)
        active["close"] = price
        active["volume"] += c["volume"]

        # Check threshold
        if abs(active["close"] - active["open"]) >= threshold:
            nt.append(active)

            # Start new candle
            active = {
                "open": price,
                "high": price,
                "low":  price,
                "close": price,
                "volume": 0
            }

    # Add last candle
    nt.append(active)

    return nt

def fetch_history_with_failover(symbol, interval="1m", range_="1d"):
    providers = choose_providers(symbol)

    # --- Symbol normalization helpers ---
    def normalize_for_alpha(sym):
        # LSE: AZN.L → AZN.LON
        if sym.endswith(".L"):
            return sym.replace(".L", ".LON")
        return sym

    def normalize_for_stooq(sym):
        # US stocks: MSTR → MSTR.US
        if sym.isalpha():
            return sym + ".US"
        return sym

    COINGECKO_MAP = {
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "DOGE": "dogecoin",
        "ADA": "cardano",
        "SOL": "solana",
        "XRP": "ripple",
        "DOT": "polkadot",
        "LTC": "litecoin",
        "BCH": "bitcoin-cash",
        "BNB": "binancecoin"
    }

    for provider_cls in providers:
        p = provider_cls()

        # Skip Yahoo (no history implemented)
        if provider_cls.__name__ == "YahooProvider":
            print("[HISTORY] Yahoo has no fetch_history()")
            continue

        # Skip Yahoo if cooling down
        if provider_cls.__name__ == "YahooProvider" and not is_yahoo_available():
            continue

        # --- Normalize symbol for this provider ---
        symbol_for_provider = symbol

        if provider_cls.__name__ == "AlphaVantageProvider":
            symbol_for_provider = normalize_for_alpha(symbol)

        elif provider_cls.__name__ == "StooqProvider":
            symbol_for_provider = normalize_for_stooq(symbol)

        elif provider_cls.__name__ == "CoinGeckoProvider":
            base = symbol.split("-")[0].upper()
            if base in COINGECKO_MAP:
                symbol_for_provider = COINGECKO_MAP[base]
            else:
                print(f"[HISTORY] CoinGecko: Unknown coin {base}")
                continue

        # --- Try fetching history ---
        try:
            if hasattr(p, "fetch_history"):
                candles = p.fetch_history(symbol_for_provider, interval, range_)
                if candles:
                    print(f"[HISTORY] {p.name} OK for {symbol} (as {symbol_for_provider})")
                    return candles
                else:
                    print(f"[HISTORY] {p.name} returned no data for {symbol_for_provider}")
            else:
                print(f"[HISTORY] {p.name} has no fetch_history()")

        except Exception as e:
            print(f"[HISTORY] {p.name} failed for {symbol_for_provider}: {e}")
            continue

    print(f"[HISTORY] No provider succeeded for {symbol}")
    return []

def scale_value(price, min_price, max_price):
    """
    Convert price to MSX SCREEN 2 Y coordinate.
    0 = top, 191 = bottom.
    We use 140..20 for chart area.
    """
    if max_price == min_price:
        return 100  # avoid division by zero

    # Chart height = 120 pixels
    chart_top = 20
    chart_bottom = 140
    chart_height = chart_bottom - chart_top

    # Normalize price
    ratio = (price - min_price) / (max_price - min_price)

    # Invert Y axis (higher price = lower Y)
    y = chart_bottom - int(ratio * chart_height)

    # Clamp
    if y < 0: y = 0
    if y > 191: y = 191

    return y

# -----------------------------
# STOCK command handler
# -----------------------------
def stock(command_str: str):
    print("stock()")
    global cache, cache_running, cache_thread, cache_interval, cache_symbols

    def fmt_volume(v):
        if v >= 1_000_000_000: return f"{v/1_000_000_000:.2f}B"
        if v >= 1_000_000: return f"{v/1_000_000:.2f}M"
        if v >= 1_000: return f"{v/1_000:.2f}K"
        return f"{v:.2f}U"

    parts = command_str.strip().split(" ", 1)
    subcmd = parts[0].upper()

    # -------------------------
    # STARTCACHE
    # -------------------------
    if subcmd == "STARTCACHE":
        print("STARTCACHE()")
        try:
            cache_interval = int(parts[1])
        except:
            sendmultiblock(b"ERROR: Use STARTCACHE <seconds>")
            return
        if cache_running:
            sendmultiblock(b"Cache already running")
            return
        cache_running = True
        cache_thread = threading.Thread(target=cache_updater, daemon=True)
        cache_thread.start()
        sendmultiblock(f"Cache started, interval={cache_interval}s".encode())
        return

    # -------------------------
    # STOPCACHE
    # -------------------------
    if subcmd == "STOPCACHE":
        cache_running = False
        sendmultiblock(b"Cache stopping...")
        return

    # -------------------------
    # STATUS
    # -------------------------
    if subcmd == "STATUS":
        with cache_lock:
            age = time.time() - cache_timestamp if cache_timestamp else -1
            count = len(cache)
        msg = (
            f"Cache running: {cache_running}\n"
            f"Symbols: {','.join(cache_symbols)}\n"
            f"Entries: {count}\n"
            f"Age: {age:.1f}s\n"
            f"Interval: {cache_interval}s"
        )
        sendmultiblock(msg.encode())
        return

    if subcmd == "HISTORY":
        if len(parts) < 2:
            sendmultiblock(b"ERROR: Use HISTORY <symbol>,<interval>,<range>")
            return

        args = parts[1].replace(" ", "").split(",")
        symbol = args[0]
        interval = args[1] if len(args) > 1 else "1m"
        range_   = args[2] if len(args) > 2 else "1d"

        candles = fetch_history_with_failover(symbol, interval, range_)

        if not candles:
            sendmultiblock(b"ERROR: No history data")
            return

        lines = []
        for i, c in enumerate(candles):
            lines.append(
                f"O({i})={c['open']}\n"
                f"H({i})={c['high']}\n"
                f"L({i})={c['low']}\n"
                f"C({i})={c['close']}\n"
                f"V({i})={c['volume']}"
            )

        sendmultiblock("\n".join(lines).encode())
        return

    # -------------------------
    # FETCHLIST
    # -------------------------
    if subcmd == "FETCHLIST":
        if len(parts) < 2:
            sendmultiblock(b"ERROR: Use FETCHLIST <symbols>")
            return

        raw_list = parts[1].replace(" ", "")
        symbols = raw_list.split(",")
        cache_symbols = symbols  # update cache list

        # Fetch batch with progressive failover
        try:
            with cache_lock:
                results = fetch_batch(symbols)
                cache = results
                cache_timestamp = time.time()
        except Exception as e:
            msg = f"ERROR: Batch request failed: {str(e)}"
            print(msg)
            sendmultiblock(msg.encode())
            return

        # Format output
        lines = []

        for sym in symbols:
            d = results.get(norm(sym))

            if not d:
                # No data at all
                line = f"{sym:<12}----   No data"
            else:
                # Display symbol (remove dash for crypto)
                disp = sym.replace("-", "")[:6].ljust(6)

                cur = float(d.get("regularMarketPrice", 0))
                o   = float(d.get("regularMarketOpen", 0))
                h   = float(d.get("regularMarketDayHigh", 0))
                l   = float(d.get("regularMarketDayLow", 0))
                pc  = float(d.get("regularMarketPreviousClose", 0))

                v_raw = int(d.get("regularMarketVolume", 0))
                v_fmt = fmt_volume(v_raw)

                # Fallback flag: "*" if using last_good, else " "
                fb_flag = "*" if d.get("_fallback") else " "

                # Append flag after volume
                line = "{:<6s}{:>10.2f}{:>10.2f}{:>10.2f}{:>10.2f}{:>10.2f}{:>12s} {}".format(
                    disp, cur, o, h, l, pc, v_fmt, fb_flag
                )

            lines.append(line)

        sendmultiblock("\n".join(lines).encode())
        return

    if subcmd == "NTCANDLE":
        if len(parts) < 2:
            sendmultiblock(b"ERROR: Use NTCANDLE <symbol>,<threshold>,<interval>,<range>")
            return

        # Parse MSX parameters
        args = parts[1].replace(" ", "").split(",")
        symbol    = args[0]
        threshold = float(args[1])
        interval  = args[2] if len(args) > 2 else "1m"
        range_    = args[3] if len(args) > 3 else "1d"

        # Fetch history using MSX parameters
        candles = fetch_history_with_failover(symbol, interval, range_)
        if not candles:
            sendmultiblock(b"ERROR: No history data")
            return

        # Build non-temporal candles
        nt = build_non_temporal_candles(candles, threshold)

        # Limit number of candles based on interval
        if interval == "1h":
            nt = nt[-24:]
        elif interval == "30m":
            nt = nt[-48:]
        elif interval == "15m":
            nt = nt[-96:]
        elif interval == "1m":
            nt = nt[-240:]

        # Compute min/max for scaling
        min_price = min(c["low"] for c in nt)
        max_price = max(c["high"] for c in nt)

        # Build DRAW commands
        lines = []
        for i, c in enumerate(nt):
            x = 8 + i*4

            yo = scale_value(c["open"],  min_price, max_price)
            yh = scale_value(c["high"],  min_price, max_price)
            yl = scale_value(c["low"],   min_price, max_price)
            yc = scale_value(c["close"], min_price, max_price)

            # Wick
            lines.append(f"D:W {x+1} {yh} {yl} 15")

            # Body color
            if c["close"] > c["open"]:
                col = 10
            elif c["close"] < c["open"]:
                col = 6
            else:
                col = 14

            # Body
            lines.append(f"D:B {x} {yo} {yc} {col}")

        lines.append("END")
        ll=lines
        print(len("\r\n".join(lines).encode()))
        sendmultiblock("\r\n".join(lines).encode())

def initialize_connection():
    if hostType == "RaspberryPi":
        init_spi_bitbang()
        GPIO.output(RPI_READY, GPIO.HIGH)
        time.sleep(0.2)
        GPIO.output(RPI_READY, GPIO.LOW)

        # Idempotent on purpose: this function is the error-recovery path for
        # the command loop below, so it runs again on every glitch.  A second
        # add_event_detect on the same channel raises "Conflicting edge
        # detection already enabled", which used to escape and kill the
        # server - turning one bad byte into a crash loop that the monitor
        # restarted for ever, with the MSX unable to boot at all.
        try:
            GPIO.remove_event_detect(RPI_SHUTDOWN)
        except Exception:
            pass
        try:
            GPIO.add_event_detect(RPI_SHUTDOWN, GPIO.FALLING,
                                  callback=button_handler, bouncetime=200)
        except Exception as e:
            # Losing the shutdown button is a far smaller problem than losing
            # the server, so carry on rather than raise.
            print(f"MSXPi Server: shutdown button unavailable ({e})")
        print(f"[MSXPi Server on {hostType}] Listening on GPIOs:\n"
              f" ** CS={SPI_CS}, CLK={SPI_SCLK}, MOSI={SPI_MOSI}, MISO={SPI_MISO}, PI_READY={RPI_READY} **\n")
        return None
    else:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((HOST, PORT))
        s.listen(1)
        print(f"[MSXPi Server on {hostType}] Listening on {HOST}:{PORT}...")
        return s

""" ============================================================================
    MSXPi Server (msxpi-server.py) main program starts here
    ============================================================================
"""

# This section reads the persistent user configuration from msxpi.ini configuration file.
# When msxpi.ini does not exist, it populates the memory variables with default values.
if exists(MSXPIHOME+'/msxpi.ini'):
    f = open(MSXPIHOME+'/msxpi.ini','r')
    idx = 0
    psetvar = []
    while True:
        line = f.readline()
        if not line:
            break
    
        if line.startswith('var'):
            var = line.split(' ')[1].split('=')[0].strip()
            value = line.replace('var ','',1).replace(var,'',1).split('=')[1].strip()
            psetvar.append([var,value])
            idx += 1
    f.close()
    if 'SPI_CS' not in str(psetvar):
        psetvar.append(["SPI_HW","False"])
        psetvar.append(["SPI_CS","21"])
        psetvar.append(["SPI_SCLK","20"])
        psetvar.append(["SPI_MOSI","16"])
        psetvar.append(["SPI_MISO","12"])
        psetvar.append(["RPI_READY","25"])
    if 'free' not in str(psetvar):
        psetvar.append(["free","free"])

else:
    psetvar = [['PATH','/home/pi/msxpi'], \
           ['DriveA','/home/pi/msxpi/disks/msxpiboot.dsk'], \
           ['DriveB','/home/pi/msxpi/disks/tools.dsk'], \
           ['DriveM','https://github.com/costarc/MSXPi/raw/master/software/target'], \
           ['DriveR1','https://www.msxarchive.nl/pub/msx/games/roms/msx1'], \
           ['DriveR2','https://www.msxarchive.nl/pub/msx/games/roms/msx2'], \
           ['WIDTH','80'], \
           ['WIFISSID','MYWIFI'], \
           ['WIFIPWD','MYWFIPASSWORD'], \
           ['WIFICOUNTRY','GB'], \
           ['DSKTMPL','/home/pi/msxpi/disks/blank.dsk'], \
           ['ROMDB','https://raw.githubusercontent.com/costarc/openMSX/master/share/softwaredb.xml'], \
           ['IRCNICK','msxpi'], \
           ['IRCADDR','chat.freenode.net'], \
           ['IRCPORT','6667'], \
           ['SPI_HW','False'], \
           ['SPI_CS','21'], \
           ['SPI_SCLK','20'], \
           ['SPI_MOSI','16'], \
           ['SPI_MISO','12'], \
           ['RPI_READY','25'], \
           ['OPENAIKEY',''], \
           ['RAPIDAPIKEY',''], \
           ['RAPIDAPIHOST',''], \
           ['FINNHUBKEY',''], \
           ['TWELVEDATAKEY',''], \
           ['ALPHAVANTAGEKEY','']]

print(f"\n** Starting MSXPi Server Version {version} Build {BuildId} **\n")

# Initialize the server
hostType = detect_host()
ShowSecurityDisclaimer()

if hostType == "RaspberryPi":
    import RPi.GPIO as GPIO

# GPIO Pins is now defined by the user
SPI_CS = int(getMSXPiVar("SPI_CS"))
SPI_SCLK = int(getMSXPiVar("SPI_SCLK"))
SPI_MOSI = int(getMSXPiVar("SPI_MOSI"))
SPI_MISO = int(getMSXPiVar("SPI_MISO"))
RPI_READY = int(getMSXPiVar("RPI_READY"))

try:
    if hostType == "RaspberryPi":
        # SPI mode: keep trying forever
        print(f"MSXPi Server waiting command:",end="")
        while True:
            try:
                DISABLETIMEOUT = True
                rc, buf = recvdata2()
                #print(f"MSXPi Server: Command received: {buf} (rc={hex(rc)})")

                if rc == RC_SUCCESS:
                    DISABLETIMEOUT = False
                        # see the SPI branch above: line noise must not be fatal
                    buf = buf.decode('utf-8', 'replace')
                    cmd, *rest = buf.split()
                    parms = " ".join(rest)
                    print(f" -> {cmd} {parms}")
                    try:
                        result = globals()[cmd.lower()](parms)
                        # If handler returned a string or bytes, send it back to MSX
                        if isinstance(result, str):
                            try:
                                sendmultiblock(result.encode())
                            except Exception:
                                # best-effort: ignore send errors here (original design often sends inside handler)
                                pass
                        elif isinstance(result, bytes):
                            try:
                                sendmultiblock(result)
                            except Exception:
                                pass
                                                        
                        print("MSXPi Server waiting command:", end="", flush=True)
                            
                    except KeyError as e:
                        # Unknown command name
                        err = f"Unknown command: {cmd}"
                        print(err)
                        try:
                            sendmultiblock(err.encode())
                        except Exception:
                            pass
                    except Exception as e:
                        err = "Pi:Error - " + str(e)
                        print(f"MSXPi Server Command error: {str(e)}")
                        try:
                            sendmultiblock(err.encode())
                        except Exception:
                            pass
                elif rc == RC_CONNERR:
                    # explicit reconnect trigger
                    print("MSXPi Server: Connection error, reinitializing...")
                    initialize_connection()
            except Exception as e:
                errcount += 1
                print(f"MSXPi Server Command error: {str(e)}")
                try:
                    sendmultiblock(("Pi:Error - " + str(e)).encode())
                except Exception:
                    pass
                # reinitialize SPI link after error
                initialize_connection()

    else:
        # TCP mode: accept loop with reconnection.
        # One listening socket for the life of the server.  Opening a new one
        # on every pass bound port 5000 a second time while the first listener
        # was still open, which SO_REUSEADDR does not permit, so the first
        # reconnect killed the server with EADDRINUSE.  It went unnoticed
        # because the READY-wait loops spun on a closed peer and never let the
        # loop come round again.
        server_socket = initialize_connection()
        while True:
            print("MSXPi Server: Waiting for MSX connection...")
            conn, addr = server_socket.accept()
            print(f" ** MSX Connected to {addr} **\n")
            # openMSX sends one byte per OUT. With Nagle on its side and
            # delayed ACK here, a /WAIT burst write (512 back-to-back bytes
            # with no reply between them) costs tens of milliseconds PER BYTE,
            # which looks exactly like a hung transfer. Ask for immediate ACKs
            # and keep our own one-byte replies prompt. openMSX should also set
            # TCP_NODELAY (see openMSX/src/MSXPiDevice.cc); this helps until
            # such a build is deployed. The Pi's GPIO link is unaffected.
            try:
                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                if hasattr(socket, 'TCP_QUICKACK'):
                    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_QUICKACK, 1)
            except OSError as exc:
                print(f"socket tuning not applied: {exc}")
            globals()['conn'] = conn
            tcp_handshake(conn)

            print(f"MSXPi Server waiting command:",end="")
            try:
                while True:
                    DISABLETIMEOUT = True
                    rc, buf = recvdata2()
                    #print(f"MSXPi Server: Command received: {buf} (rc={hex(rc)})")

                    if rc == RC_SUCCESS and buf is not None:
                        DISABLETIMEOUT = False
                        # errors='replace' rather than raising: a byte of line
                        # noise then becomes an unrecognised command, which the
                        # loop already handles by resyncing, instead of an
                        # exception that tears down the connection.
                        buf = buf.decode('utf-8', 'replace')
                        cmd, *rest = buf.split()
                        parms = " ".join(rest)
                        print(f" -> {cmd} {parms}")
                        try:
                            if (cmd.lower() == "set"): #workaround to avoid callign Linux "set" command
                                cmd = "pset"
                            result = globals()[cmd.lower()](parms)
                            # If handler returned a string or bytes, send it back to MSX
                            if isinstance(result, str):
                                try:
                                    sendmultiblock(result.encode())
                                except Exception:
                                    # best-effort: ignore send errors here (original design often sends inside handler)
                                    pass
                            elif isinstance(result, bytes):
                                try:
                                    sendmultiblock(result)
                                except Exception:
                                    pass
                                    
                            print("MSXPi Server waiting command:", end="", flush=True)
                            
                        except KeyError as e:
                            # Unknown command name
                            err = f"MSXPi Server Error: Unknown command {cmd}"
                            print(err)
                            try:
                                sendmultiblock(err.encode())
                            except Exception:
                                pass
                        except Exception as e:
                            err = "Pi:Error - " + str(e)
                            print(f"MSXPi Server Command error: {str(e)}")
                            try:
                                sendmultiblock(err.encode())
                            except Exception:
                                pass
                    elif rc == RC_CONNERR:
                        print("MSXPi Server: Protocol error, forcing reconnect")
                        break  # exit inner loop to reaccept

            except (ConnectionResetError, BrokenPipeError, OSError) as e:
                print(f"MSXPi Server: connection lost: {e}")
            except Exception as e:
                errcount += 1
                print(f"MSXPi Server Error: {str(e)}")
                try:
                    sendmultiblock(("Pi:Error - " + str(e)).encode())
                except Exception:
                    pass
            finally:
                try:
                    conn.close()
                except Exception:
                    pass
                print("MSXPi Server: Client disconnected, waiting for new connection...")

except KeyboardInterrupt:
    if hostType == "RaspberryPi":
        GPIO.cleanup()
    try:
        if server_socket:
            server_socket.close()
    except Exception:
        pass
    for disk in (globals().get("drive0Data"), globals().get("drive1Data")):
        unmount_drive(disk)
    print("MSXPi Server: Terminating")
