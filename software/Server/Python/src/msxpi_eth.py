# MSXPi Interface
# Version 1.7.0
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
import sys
import threading
import collections

# --- Wire protocol ----------------------------------------------------------
#
# The MSX signals a fast op by sending an opcode byte where link_recv() is
# waiting for READY ($AA).  link_recv() ignores every non-READY byte, so the
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
OP_PROBE3      = 0xCA   # OP_PROBE of a protocol 3 driver (the BIOS-only half)
# 0xC9 is taken by msxpi_netplay.py (served in msxpi_ethglue, not by the shuttle).

# frozenset, not a tuple: this is tested against EVERY byte the server reads
# while waiting for READY, so a linear scan is paid on all ordinary traffic too,
# not just on opcodes.
OPCODES = frozenset((OP_PROBE, OP_GET_HWADD, OP_GET_NETSTAT, OP_NET_ONOFF,
                     OP_FILTERS, OP_IN_STATUS, OP_GET_FRAME, OP_SEND_FRAME,
                     OP_RESET, OP_PROBE3))

# Fast ops answer with [RC] followed by a fixed number of data bytes.  The
# length is a property of the opcode, known to both sides in advance, so there
# is never any framing ambiguity - even after an aborted transfer, both ends
# resynchronise on the next opcode.
FAST_REPLY_LEN = {
    OP_PROBE:       4,   # 'E','T','H', protocol version
    OP_PROBE3:      4,
    OP_GET_HWADD:   6,   # MAC address
    OP_GET_NETSTAT: 1,   # 0 = closed, 1 = open
    OP_NET_ONOFF:   1,   # resulting state
    OP_FILTERS:     1,   # resulting filter bits
    OP_RESET:       1,   # 0 = ok
}

# The ROM driver compares this with its own ETH_PROTO (ethops.asm) and refuses
# a mismatch - there is no fallback, the ROM and the server are updated
# together.  2: ETH_IN_STATUS carries small frames inline, ETH_GET_FRAME's
# maxlen 0 discards without sending the frame, and ETH_SEND_FRAME's payload is
# received as one RDY-held burst, so that the MSX can send it with OTIR.
PROTO_VERSION = 2

# Protocol 3 (documents/LINK2-DESIGN.md 4), chosen by OP_PROBE3: the same
# operations, but every burst the Pi sends starts with the GO byte and every
# block it takes (ETH_SEND_FRAME's payload) is announced by one, so the MSX can
# read GO polled and never starts INIR/OTIR before the run is up; and a good
# result code is RC_OK3, because an idle or out-of-step link reads 0.
PROTO_VERSION3 = 3
ETH_RC_OK3     = 0x5A
ETH_GO         = 0x5A

# ETH_IN_STATUS reply flag: no frame / a frame is waiting / the frame follows.
IN_NONE   = 0
IN_WAIT   = 1
IN_INLINE = 2

# A frame this size or smaller is sent with the ETH_IN_STATUS reply instead of
# waiting for ETH_GET_FRAME.  It is the size of the MSX's buffer for it
# (RX_INLINE_MAX in asm-common/include/unapi_wrk.inc): change both together,
# and bump PROTO_VERSION.
RX_INLINE_MAX = 128

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
        # A real LAN delivers every broadcast, multicast and neighbour's frame to the TAP device; the MSX cannot afford to
        # fetch them (PLAYNET-TCPIP-PERFORMANCE.md D5). Only the TAP links turn this on.
        self.lan_filter = os.environ.get("MSXPI_ETH_FILTER", "1") != "0"
        self.lan_filter_active = False
        self.filtered = 0
        self.msx_ip = None

    # --- LAN filter -----------------------------------------------------------

    def learn(self, frame):
        """Note the MSX's IP address from a frame it sends (the Pi is not told it)."""
        if len(frame) < 34 or frame[6:12] != self.mac:
            return
        et = (frame[12] << 8) | frame[13]
        if et == 0x0806 and len(frame) >= 42:
            self.msx_ip = bytes(frame[28:32])                  # ARP sender protocol address
        elif et == 0x0800 and frame[26:30] != bytes(4):
            self.msx_ip = bytes(frame[26:30])                  # IPv4 source

    def wanted(self, frame):
        """Is this received frame one the MSX would use? Its own MAC; ARP for its IP; DHCP. Not other hosts' unicast,
        not multicast, not other broadcasts. ETH_FILTERS promiscuous (bit 4) takes everything, 'accept broadcast' (bit 2) is
        required for the broadcasts."""
        if self.filters & 0x10:
            return True
        if len(frame) < 14:
            return False
        dst = bytes(frame[0:6])
        if dst == self.mac:
            return True
        if dst != bytes([255]) * 6 or not self.filters & 0x04:
            return False
        et = (frame[12] << 8) | frame[13]
        if et == 0x0806:                                       # ARP request or announcement
            return len(frame) >= 42 and (self.msx_ip is None or bytes(frame[38:42]) == self.msx_ip)
        if et == 0x0800 and len(frame) >= 38 and frame[23] == 17:   # UDP
            ihl = (frame[14] & 0x0F) * 4
            if len(frame) >= 14 + ihl + 4:
                port = (frame[14 + ihl + 2] << 8) | frame[14 + ihl + 3]
                return port in (67, 68)                        # DHCP
        return False

    # --- receive side -------------------------------------------------------

    def _push(self, frame):
        """Called by the reader thread.  Never blocks the MSX side."""
        if not self.enabled:
            return
        if len(frame) > MAX_FRAME:
            self.dropped += 1
            return
        if self.lan_filter and self.lan_filter_active and not self.wanted(frame):
            self.filtered += 1
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
        self.lan_filter_active = True
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


class WinTapLink(BaseLink):
    """A TAP-Windows (OpenVPN tap-windows6) adapter, the Windows sibling of
    TapLink.

    Same contract and same wire format: the device carries raw Ethernet
    frames, exactly as the Linux TAP does, so the shuttle, ARP handling and the
    whole UNAPI path above are untouched.

    Two Windows specifics drive the shape of this:

    1. The device is opened with FILE_FLAG_OVERLAPPED, which is what lets a
       read be abandoned when close() is called instead of wedging the thread
       until a frame happens to arrive.  Overlapped handles mean EVERY
       ReadFile/WriteFile must pass an OVERLAPPED, including the writes.
    2. The adapter reports "cable unplugged" to Windows until
       TAP_IOCTL_SET_MEDIA_STATUS says otherwise.  Without that call the
       address the setup script assigned stays inactive, nothing routes, and
       the failure looks like a misconfigured network rather than a missing
       ioctl.

    Opening it does NOT need administrator rights - verified against
    tap-windows6 from an unelevated process.  Only creating the adapter and
    writing the address and NAT rules do, which is why that lives in a setup
    script run once rather than in the server.
    """

    # Adapter enumeration lives in the registry; there is no friendlier API
    # without pulling in setupapi.
    ADAPTER_KEY = (r"SYSTEM\CurrentControlSet\Control\Class"
                   r"\{4D36E972-E325-11CE-BFC1-08002BE10318}")
    CONN_KEY = (r"SYSTEM\CurrentControlSet\Control\Network"
                r"\{4D36E972-E325-11CE-BFC1-08002BE10318}")

    # CTL_CODE(FILE_DEVICE_UNKNOWN=0x22, function, METHOD_BUFFERED=0,
    #          FILE_ANY_ACCESS=0)
    TAP_IOCTL_GET_MTU = (0x22 << 16) | (3 << 2)
    TAP_IOCTL_SET_MEDIA_STATUS = (0x22 << 16) | (6 << 2)

    GENERIC_READ = 0x80000000
    GENERIC_WRITE = 0x40000000
    OPEN_EXISTING = 3
    FILE_ATTRIBUTE_SYSTEM = 0x4
    FILE_FLAG_OVERLAPPED = 0x40000000
    ERROR_IO_PENDING = 997
    WAIT_TIMEOUT_ = 0x102          # not WAIT_TIMEOUT: that name is a macro
    INFINITE = 0xFFFFFFFF

    @classmethod
    def find_adapters(cls):
        """Every tap-windows adapter, as (guid, friendly name).

        ComponentId is "tap0901" on some installs and "root\\tap0901" on
        others - the OpenVPN installer has used both - so match on the
        substring rather than on equality.
        """
        import winreg
        found = []
        try:
            key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, cls.ADAPTER_KEY)
        except OSError:
            return found
        with key:
            for i in range(winreg.QueryInfoKey(key)[0]):
                try:
                    with winreg.OpenKey(key, winreg.EnumKey(key, i)) as sub:
                        cid = winreg.QueryValueEx(sub, "ComponentId")[0]
                        if "tap0901" not in str(cid).lower():
                            continue
                        guid = winreg.QueryValueEx(sub, "NetCfgInstanceId")[0]
                except OSError:
                    continue
                name = guid
                try:
                    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                                        cls.CONN_KEY + "\\" + guid +
                                        r"\Connection") as conn:
                        name = winreg.QueryValueEx(conn, "Name")[0]
                except OSError:
                    pass
                found.append((guid, name))
        return found

    # Where the setup script's address lives: netsh writes a static address to
    # IPAddress, DHCP to DhcpIPAddress.  Read from the registry, like the
    # adapter list, so choosing an adapter needs no subprocess.
    TCPIP_KEY = r"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"

    @classmethod
    def adapter_ips(cls, guid):
        """IPv4 addresses Windows has configured on the adapter with this GUID."""
        import winreg
        ips = []
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                                cls.TCPIP_KEY + "\\" + guid) as k:
                for name in ("IPAddress", "DhcpIPAddress"):
                    try:
                        v = winreg.QueryValueEx(k, name)[0]
                    except OSError:
                        continue
                    ips += [v] if isinstance(v, str) else list(v)
        except OSError:
            pass
        return [ip for ip in ips if ip]

    @classmethod
    def pick_adapter(cls, adapters, ifname=None, tap_ip=None):
        """Choose the (guid, name) to open.

        A PC can have several TAP adapters (a second one for a second openMSX).
        The one to open is the one msxpi-tcpip-setup.ps1 gave the gateway
        address, so that is matched first; the registry order, which has nothing
        to do with it, is only the last resort.  An explicit name still wins.
        """
        if ifname:
            named = [a_ for a_ in adapters if a_[1] == ifname]
            if named:
                return named[0]
        if tap_ip:
            for a_ in adapters:
                if tap_ip in cls.adapter_ips(a_[0]):
                    return a_
        return adapters[0]

    def __init__(self, ifname=None, tap_ip=None, *a, **kw):
        BaseLink.__init__(self, *a, **kw)
        import ctypes
        import ctypes.wintypes as wintypes
        self.lan_filter_active = True
        self._ctypes = ctypes
        self._wintypes = wintypes

        adapters = self.find_adapters()
        if not adapters:
            raise OSError("no TAP-Windows adapter found - install the "
                          "OpenVPN TAP driver, then run msxpi-tcpip-setup.ps1")
        self.guid, self.ifname = self.pick_adapter(adapters, ifname, tap_ip)

        self._k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self._k32.CreateFileW.restype = wintypes.HANDLE
        self._k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD,
                                          wintypes.DWORD, ctypes.c_void_p,
                                          wintypes.DWORD, wintypes.DWORD,
                                          wintypes.HANDLE]
        self._k32.CreateEventW.restype = wintypes.HANDLE

        path = "\\\\.\\Global\\" + self.guid + ".tap"
        handle = self._k32.CreateFileW(
            path, self.GENERIC_READ | self.GENERIC_WRITE, 0, None,
            self.OPEN_EXISTING,
            self.FILE_ATTRIBUTE_SYSTEM | self.FILE_FLAG_OVERLAPPED, None)
        if handle == wintypes.HANDLE(-1).value:
            err = ctypes.get_last_error()
            raise OSError(err, "cannot open %s (WinError %d)%s"
                          % (self.ifname, err,
                             " - another program has it open"
                             if err == 32 else ""))
        self.handle = handle

        # Report the cable as connected, or the adapter's address never
        # becomes active. Done before the reader starts so no frame can be
        # missed between the two.
        on = ctypes.c_ulong(1)
        ret = wintypes.DWORD()
        if not self._k32.DeviceIoControl(handle, self.TAP_IOCTL_SET_MEDIA_STATUS,
                                         ctypes.byref(on), 4,
                                         ctypes.byref(on), 4,
                                         ctypes.byref(ret), None):
            err = ctypes.get_last_error()
            self._k32.CloseHandle(handle)
            self.handle = None
            raise OSError(err, "TAP_IOCTL_SET_MEDIA_STATUS failed (WinError %d)"
                          % err)

        self._write_lock = threading.Lock()
        self._read_event = self._k32.CreateEventW(None, True, False, None)
        self._write_event = self._k32.CreateEventW(None, True, False, None)

        self.enabled = True
        self.thread = threading.Thread(target=self._reader, name="msxpi-wintap")
        self.thread.daemon = True
        self.thread.start()

    def _overlapped(self, event):
        """An OVERLAPPED carrying `event`, as a plain buffer.

        Declared here rather than as a ctypes.Structure at module scope so
        this file still imports on Linux, where ctypes.wintypes does not.
        """
        ctypes = self._ctypes
        buf = (ctypes.c_ubyte * (ctypes.sizeof(ctypes.c_void_p) * 3 +
                                 ctypes.sizeof(ctypes.c_ulong) * 2))()
        # OVERLAPPED: Internal, InternalHigh, Offset, OffsetHigh, hEvent.
        # Only hEvent has to be set; the rest start zeroed, which is what the
        # API requires for a device that does not support offsets.
        ctypes.memmove(ctypes.byref(buf, ctypes.sizeof(buf) -
                                    ctypes.sizeof(ctypes.c_void_p)),
                       ctypes.byref(ctypes.c_void_p(event)),
                       ctypes.sizeof(ctypes.c_void_p))
        return buf

    def _reader(self):
        ctypes = self._ctypes
        wintypes = self._wintypes
        buf = (ctypes.c_ubyte * (MAX_FRAME + 4))()
        got = wintypes.DWORD()
        while self.running:
            ov = self._overlapped(self._read_event)
            self._k32.ResetEvent(self._read_event)
            ok = self._k32.ReadFile(self.handle, ctypes.byref(buf), len(buf),
                                    ctypes.byref(got), ctypes.byref(ov))
            if not ok:
                if ctypes.get_last_error() != self.ERROR_IO_PENDING:
                    if self.running:
                        continue
                    break
                # Wake up regularly so close() ends this thread promptly,
                # exactly as the select() timeout does on Linux.
                while self.running:
                    if self._k32.WaitForSingleObject(self._read_event,
                                                     250) != self.WAIT_TIMEOUT_:
                        break
                if not self.running:
                    break
                if not self._k32.GetOverlappedResult(self.handle,
                                                     ctypes.byref(ov),
                                                     ctypes.byref(got), False):
                    continue
            if got.value:
                self._push(bytes(bytearray(buf[:got.value])))

    def transmit(self, frame):
        ctypes = self._ctypes
        wintypes = self._wintypes
        if self.handle is None:
            return False
        data = (ctypes.c_ubyte * len(frame)).from_buffer_copy(frame)
        sent = wintypes.DWORD()
        with self._write_lock:
            ov = self._overlapped(self._write_event)
            self._k32.ResetEvent(self._write_event)
            ok = self._k32.WriteFile(self.handle, ctypes.byref(data),
                                     len(frame), ctypes.byref(sent),
                                     ctypes.byref(ov))
            if not ok:
                if ctypes.get_last_error() != self.ERROR_IO_PENDING:
                    return False
                self._k32.WaitForSingleObject(self._write_event, self.INFINITE)
                if not self._k32.GetOverlappedResult(self.handle,
                                                     ctypes.byref(ov),
                                                     ctypes.byref(sent), False):
                    return False
        return True

    def link_up(self):
        return self.handle is not None

    def close(self):
        # Order matters: stop the reader and WAIT for it before closing the
        # handle. Closing first leaves that thread inside GetOverlappedResult
        # on a handle Windows is free to hand to something else - a
        # use-after-close that would corrupt whichever file got the reused
        # value, and only under a race. Signalling the event makes it notice
        # at once instead of after the 250 ms poll.
        BaseLink.close(self)
        handle, self.handle = self.handle, None
        thread = getattr(self, "thread", None)
        if thread is not None and thread.is_alive():
            if getattr(self, "_read_event", None):
                self._k32.SetEvent(self._read_event)
            if handle is not None:
                self._k32.CancelIoEx(handle, None)
            thread.join(timeout=2.0)
        if handle is not None:
            self._k32.CloseHandle(handle)
        for ev in (getattr(self, "_read_event", None),
                   getattr(self, "_write_event", None)):
            if ev:
                self._k32.CloseHandle(ev)
        self._read_event = self._write_event = None


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

    read_burst(n) -> bytes or None, optional; the mirror image for OTIR.
    ETH_SEND_FRAME's payload always arrives through it when it is given: the
    driver sends it with OTIR in wait mode, and a byte that lands while READY
    is down is lost, not delayed.  A polled driver works through it too - it
    simply finds READY up for every byte.

    write_burst is what lets the MSX use INIR.  Hardware /WAIT is gated on
    SPI_RDY, and the per-byte link_recv_byte() raises and drops RPI_READY
    around every single byte - during that gap an INIR read would NOT stall and
    would silently return a stale byte.  A burst-capable transport must hold
    RPI_READY high for the whole run.  Without one, everything here still works
    via write_byte, just at legacy speed.
    """

    def __init__(self, link, read_byte, write_byte, write_burst=None,
                 read_burst=None, log=None, write_burst_go=None,
                 read_burst_go=None, load_proto=None, save_proto=None):
        self.link = link
        self._read = read_byte
        self._write = write_byte
        self._burst = write_burst
        self._read_burst = read_burst
        # Protocol 3: the same two, with the GO byte inside the READY-held run
        # (msxpi_transport.spi_burst_send / spi_burst_recv).
        self._burst_go = write_burst_go
        self._read_burst_go = read_burst_go
        self._log = log or (lambda *a: None)
        # The protocol the last probe chose, kept by the caller (ETHPROTO in
        # msxpi.ini, see msxpi_ethglue): load_proto() -> 2, 3 or None, and
        # save_proto(version).  None: not kept.
        self._load_proto = load_proto
        self._save_proto = save_proto

        # Dict dispatch, built once, instead of an if/elif chain walked on every
        # opcode. Bound methods are stored directly so a call costs one dict
        # lookup rather than up to nine comparisons plus an attribute lookup.
        #
        # Worth doing because the per-transaction fixed cost - not the per-byte
        # cost - dominates short transactions, and ETH_IN_STATUS is a 6-byte
        # transaction InterNestor Lite issues sixty times a second.
        self._dispatch = {
            OP_PROBE:       self._op_probe,
            OP_PROBE3:      self._op_probe3,
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
        self._set_proto(self._saved_proto())

    def _saved_proto(self):
        """The protocol the last probe chose, kept across a server restart.

        A driver probes only when it starts and on ETH_RESET, so a restarted
        server that fell back to 2 would answer a protocol 3 driver with no GO
        and RC_OK 0: every transaction fails until the MSX is reset.  The DOS
        half's driver probes with OP_PROBE when it starts, so a value left at 3
        cannot mislead it.
        """
        if self._load_proto is not None:
            try:
                return 3 if self._load_proto() == 3 else 2
            except Exception as exc:
                self._log("eth: cannot read the kept protocol: %s" % exc)
        return 2

    def _probe(self, version):
        if version != self.proto and self._save_proto is not None:
            try:
                self._save_proto(version)
            except Exception as exc:
                self._log("eth: cannot keep the protocol: %s" % exc)
        self._set_proto(version)
        self._write_many(self._probe_reply)

    def _set_proto(self, version):
        """Serve the driver in protocol 2 or 3 until its next probe."""
        self.proto = version
        self._ok = ETH_RC_OK3 if version == 3 else ETH_RC_OK
        self._probe_reply = (bytes([self._ok]) + b"ETH"
                             + bytes([PROTO_VERSION3 if version == 3 else PROTO_VERSION]))
        self._netstat_up   = bytes([self._ok, 1])
        self._netstat_down = bytes([self._ok, 0])

    def _op_probe(self):
        self._probe(2)

    def _op_probe3(self):
        self._probe(3)

    def _op_get_hwadd(self):
        self._fast(self._ok, self.link.mac)

    def _op_get_netstat(self):
        self._write_many(self._netstat_up if self.link.link_up()
                         else self._netstat_down)

    # --- helpers ------------------------------------------------------------

    def _write_many(self, data):
        if self.proto == 3:
            # GO and the reply in one run
            if self._burst_go is not None:
                return self._burst_go(bytes(data))
            return self._write_many_plain(bytes([ETH_GO]) + bytes(data))
        return self._write_many_plain(data)

    def _write_many_plain(self, data):
        if self._burst is not None:
            return self._burst(bytes(data))
        for b in bytearray(data):
            rc = self._write(b)
            if rc:
                return rc
        return 0

    def _read_block(self, n):
        """n bytes the MSX sends as one block (OTIR), READY held throughout."""
        if self.proto == 3:
            if self._read_burst_go is not None:
                return self._read_burst_go(n)
            if self._write(ETH_GO):
                return None
        if self._read_burst is not None:
            return self._read_burst(n)
        return self._read_n(n)

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
        self._fast(self._ok, bytes([1 if self.link.enabled else 2]))

    def _op_filters(self):
        """ETH_FILTERS.  Bit 7 of the argument means "report only, change
        nothing" - that is the specification's own encoding, so the byte is
        passed through from the MSX untranslated."""
        rc, arg = self._read()
        if arg is None:
            return
        if not (arg & 0x80):
            self.link.filters = arg & 0x7F
        self._fast(self._ok, bytes([self.link.filters]))

    def _op_reset(self):
        """ETH_RESET: back to the state defined in specification section 3.2 -
        networking enabled, queued frames discarded, default filters."""
        with self.link.lock:
            self.link.rx.clear()
        self.link.dropped = 0
        self.link.enabled = True
        self.link.filters = 0x06
        self._fast(self._ok, bytes([0]))

    def _op_in_status(self):
        """ETH_IN_STATUS.  Reply: [FLAG][LEN_LO][LEN_HI][ET_HI][ET_LO], and
        when FLAG is IN_INLINE the frame and its checksum straight after.

        FLAG 0 means no frame, 1 a frame is waiting (fetch it with
        ETH_GET_FRAME), 2 here it is.  LEN and the ether-type go straight into
        the routine's BC and HL.

        A small frame comes inline so that receiving it costs the MSX one
        transaction instead of two; it is taken off the queue as it is sent,
        and the driver holds it until ETH_GET_FRAME asks.  Only this thread
        pops, so the frame peek() saw is the one pop() returns.
        """
        length, et = self.link.peek()
        if not length:
            self._write_many(bytes(5))
            return
        head = [IN_WAIT, length & 0xFF, (length >> 8) & 0xFF,
                (et >> 8) & 0xFF, et & 0xFF]
        if length > RX_INLINE_MAX:
            self._write_many(bytes(head))
            return
        frame, _more = self.link.pop()
        head[0] = IN_INLINE
        self._write_many(bytes(head) + frame
                         + bytes([sum(bytearray(frame)) & 0xFF]))

    def _op_get_frame(self):
        """ETH_GET_FRAME.

        MSX -> [C6][MAXLEN_LO][MAXLEN_HI]
        Pi  -> [LEN_LO][LEN_HI][FLAGS]                      when LEN == 0
               [LEN_LO][LEN_HI][FLAGS][frame...][CHKSUM]    otherwise

        MAXLEN 0 asks to discard the frame (ETH_GET_FRAME with HL=0): it is
        dropped here and only the header goes back, so throwing a frame away
        no longer drags all of it across the link.

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

        if not maxlen:
            self._write_many(bytes([len(frame) & 0xFF, (len(frame) >> 8) & 0xFF,
                                    FLAG_MORE_PENDING if more else 0]))
            return

        if len(frame) > maxlen:
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

        The opcode and the length come byte by byte; the frame and its
        checksum as ONE block, which the driver sends with OTIR in wait mode.
        """
        hdr = self._read_n(2)
        if hdr is None:
            return
        length = hdr[0] | (hdr[1] << 8)

        if length < MIN_FRAME or length > MAX_FRAME:
            self._write(ETH_RC_BADLEN)
            return

        block = self._read_block(length + 1)
        if block is None:
            return
        body, chk = bytes(block[:-1]), block[-1]

        if (sum(bytearray(body)) & 0xFF) != chk:
            self._log("eth: send checksum mismatch")
            self._write(ETH_RC_CHKSUM)
            return

        # Pad, then append the FCS the TAP device does not supply.
        out = body
        if len(out) < PAD_TO:
            out = out + b"\x00" * (PAD_TO - len(out))
        out = out + struct.pack("<I", eth_crc32(out))

        self.link.learn(body)
        ok = self.link.transmit(out)
        self._write(self._ok if ok else ETH_RC_ERR)


# =============================================================================
# Factory
# =============================================================================

# The gateway address msxpi-tcpip-setup.ps1 puts on the TAP-Windows adapter
# (its -TapIp default).  Overridable with TAPIP in msxpi.ini.
DEFAULT_TAP_IP = "192.168.99.1"


def make_link(prefer_tap=True, ifname="msxpi0", log=None, tap_ip=None):
    """A TapLink where possible, a MockLink everywhere else.

    Falling back rather than raising is deliberate: the openMSX harness runs on
    Windows, where there is no /dev/net/tun, and every phase before real
    networking is exercised entirely through MockLink.
    """
    log = log or (lambda *a: None)
    if os.environ.get("MSXPI_ETH_LINK") == "udpnat":
        # test rigs: a user-mode UDP network inside this process (msxpi_ethnat.py)
        from msxpi_ethnat import UdpNatLink
        log("eth: user-mode UDP link (10.0.2.0/24, host 10.0.2.2)")
        return UdpNatLink(log=log)
    if prefer_tap and os.path.exists("/dev/net/tun"):
        try:
            link = TapLink(ifname=ifname)
            log("eth: TAP device %s up" % ifname)
            return link
        except Exception as e:
            log("eth: TAP unavailable (%s) - falling back to MockLink" % e)
    elif prefer_tap and sys.platform == "win32":
        # TAP-Windows carries the same raw Ethernet frames as the Linux TAP,
        # so everything above this line is unchanged. Opening it needs no
        # administrator rights; assigning the address and the NAT does, and
        # that is msxpi-tcpip-setup.ps1's job, run once.
        try:
            link = WinTapLink(ifname=None if ifname == "msxpi0" else ifname,
                              tap_ip=tap_ip or DEFAULT_TAP_IP)
            log("eth: TAP device %s up (selected for %s)"
                % (link.ifname, tap_ip or DEFAULT_TAP_IP))
            return link
        except Exception as e:
            log("eth: TAP unavailable (%s) - falling back to MockLink" % e)
    else:
        log("eth: no /dev/net/tun - using MockLink")
    return MockLink()
