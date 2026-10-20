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

# =============================================================================
# msxpi_ethnat.py - a user-mode UDP/TCP link for the Ethernet UNAPI shuttle
# =============================================================================
# A third link beside TapLink and WinTapLink, for test rigs: no TAP device, no
# administrator rights, nothing outside this process.  It plays the rest of a
# small network to the MSX, the way slirp does for QEMU:
#
#   10.0.2.0/24     the MSX is whatever address it uses (INL.CFG: ip l 10.0.2.15)
#   10.0.2.2        "the host": UDP and TCP to it go to 127.0.0.1, ICMP echo answered
#   anything else   UDP and TCP go out to that address as they are
#
# Every UDP source port the MSX uses gets one host socket, bound to the SAME port
# number when it is free, so a test can tell the other side in advance where the
# MSX is (127.0.0.1:<that port>).  Datagrams arriving on it are handed to the MSX
# from 10.0.2.2 when they came from 127.0.0.1, else from their real address.
# ARP: every address but the MSX's own is answered with the host MAC.
#
# TCP (for the chat's IRC connection): each connection the MSX opens is a host socket.
# The link answers the handshake itself, passes in-order data on and acknowledges it,
# and sends what the host side receives in segments within the MSX's window, keeping
# them until they are acknowledged and sending them again after a second.  No options,
# no out-of-order queue (the MSX side sends again what was not acknowledged).
#
# Selected with MSXPI_ETH_LINK=udpnat (msxpi_eth.make_link).
# =============================================================================

import socket
import struct
import threading
import time

from msxpi_eth import BaseLink

HOST_IP = bytes([10, 0, 2, 2])
HOST_MAC = b"\x52\x54\x00\x12\x35\x02"
BROADCAST = b"\xff" * 6
ET_IP, ET_ARP = 0x0800, 0x0806


def checksum(data):
    if len(data) & 1:
        data += b"\x00"
    s = sum(struct.unpack("!%dH" % (len(data) // 2), data))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


class UdpNatLink(BaseLink):
    def __init__(self, log=None, *a, **kw):
        BaseLink.__init__(self, *a, **kw)
        self.log = log or (lambda *x: None)
        self.msx_mac = None
        self.msx_ip = None
        self.socks = {}                  # MSX UDP port -> host socket
        self.ident = 0
        self.slock = threading.Lock()
        self.tcp = {}                    # (msx port, ip, port) -> TcpConn
        threading.Thread(target=self._tcp_timer, daemon=True).start()

    def link_up(self):
        return True

    def close(self):
        BaseLink.close(self)
        with self.slock:
            for s in self.socks.values():
                s.close()
            self.socks.clear()

    # --- MSX -> network -----------------------------------------------------

    def transmit(self, frame):
        frame = bytes(frame)
        if len(frame) < 14:
            return True
        et = struct.unpack("!H", frame[12:14])[0]
        if et == ET_ARP:
            self._arp(frame)
        elif et == ET_IP:
            self._ip(frame)
        return True

    def _arp(self, frame):
        a = frame[14:42]
        if len(a) < 28 or struct.unpack("!H", a[6:8])[0] != 1:      # requests only
            return
        sha, spa, tpa = a[8:14], a[14:18], a[24:28]
        self.msx_mac, self.msx_ip = sha, spa
        if tpa == spa or spa == b"\x00\x00\x00\x00":                # gratuitous, or a probe for its own address
            return
        reply = struct.pack("!HHBBH", 1, ET_IP, 6, 4, 2) + HOST_MAC + tpa + sha + spa
        self._push(sha + HOST_MAC + struct.pack("!H", ET_ARP) + reply)

    def _ip(self, frame):
        ip = frame[14:]
        if len(ip) < 20 or ip[0] >> 4 != 4:
            return
        ihl = (ip[0] & 15) * 4
        total = struct.unpack("!H", ip[2:4])[0]
        proto, src, dst = ip[9], ip[12:16], ip[16:20]
        payload = ip[ihl:total]
        self.msx_mac, self.msx_ip = frame[6:12], src
        if proto == 6 and len(payload) >= 20:
            self._tcp_in(src, dst, payload)
        elif proto == 17 and len(payload) >= 8:
            sport, dport = struct.unpack("!HH", payload[:4])
            data = payload[8:struct.unpack("!H", payload[4:6])[0]]
            host = "127.0.0.1" if dst == HOST_IP else socket.inet_ntoa(dst)
            try:
                self._sock(sport).sendto(data, (host, dport))
            except OSError as e:
                self.log("ethnat: udp to %s:%d failed: %s" % (host, dport, e))
        elif proto == 1 and dst == HOST_IP and len(payload) >= 8 and payload[0] == 8:   # ping the host
            reply = b"\x00\x00\x00\x00" + payload[4:]
            reply = reply[:2] + struct.pack("!H", checksum(reply)) + reply[4:]
            self._push_ip(1, HOST_IP, src, reply)

    def _sock(self, port):
        with self.slock:
            s = self.socks.get(port)
            if s:
                return s
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                s.bind(("0.0.0.0", port))
            except OSError:
                s.bind(("0.0.0.0", 0))
            self.socks[port] = s
            self.log("ethnat: MSX UDP port %d is host port %d" % (port, s.getsockname()[1]))
            threading.Thread(target=self._reader, args=(s, port), daemon=True).start()
            return s

    # --- network -> MSX -----------------------------------------------------

    def _reader(self, s, port):
        while self.running:
            try:
                data, (host, hport) = s.recvfrom(2048)
            except OSError:
                if s.fileno() == -1:
                    return
                continue                 # Windows: ICMP port unreachable from an earlier send
            src = HOST_IP if host.startswith("127.") else socket.inet_aton(host)
            udp = struct.pack("!HHHH", hport, port, 8 + len(data), 0) + data
            pseudo = src + (self.msx_ip or b"\x00" * 4) + struct.pack("!BBH", 0, 17, len(udp))
            udp = udp[:6] + struct.pack("!H", checksum(pseudo + udp) or 0xFFFF) + udp[8:]
            self._push_ip(17, src, self.msx_ip, udp)

    # --- TCP --------------------------------------------------------------------

    def _tcp_in(self, src, dst, seg):
        sport, dport, seq, ack, off, flags, win = struct.unpack('!HHIIBBH', seg[:16])
        data = seg[(off >> 4) * 4:]
        key = (sport, dst, dport)
        with self.slock:
            c = self.tcp.get(key)
        if flags & 0x04:                                  # RST
            if c:
                c.close()
            return
        if flags & 0x02 and not flags & 0x10:              # SYN: a new connection
            if c:
                c.close()
            c = TcpConn(self, key, src, seq)
            with self.slock:
                self.tcp[key] = c
            c.open()
            return
        if not c:
            self._tcp_send(dst, src, dport, sport, ack, seq + len(data) + (1 if flags & 1 else 0), 0x14, b'')
            return
        c.on_segment(seq, ack, flags, win, data)

    def _tcp_send(self, src, dst, sport, dport, seq, ack, flags, data, win=8192):
        hdr = struct.pack('!HHIIBBHHH', sport, dport, seq & 0xFFFFFFFF, ack & 0xFFFFFFFF, 5 << 4, flags, win, 0, 0)
        seg = hdr + data
        pseudo = src + dst + struct.pack('!BBH', 0, 6, len(seg))
        seg = seg[:16] + struct.pack('!H', checksum(pseudo + seg)) + seg[18:]
        self._push_ip(6, src, dst, seg)

    def _tcp_timer(self):
        while self.running:
            time.sleep(0.25)
            with self.slock:
                conns = list(self.tcp.values())
            for c in conns:
                c.tick()

    def _push_ip(self, proto, src, dst, payload):
        if not self.msx_mac or not dst:
            return
        self.ident = (self.ident + 1) & 0xFFFF
        hdr = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(payload), self.ident, 0, 64, proto, 0, src, dst)
        hdr = hdr[:10] + struct.pack("!H", checksum(hdr)) + hdr[12:]
        self._push(self.msx_mac + HOST_MAC + struct.pack("!H", ET_IP) + hdr + payload)


class TcpConn:
    """One TCP connection of the MSX, carried by a host socket."""
    MSS = 512

    def __init__(self, link, key, msx_ip, msx_isn):
        self.link, self.key, self.msx_ip = link, key, msx_ip
        self.msx_port, self.ip, self.port = key
        self.rcv_nxt = (msx_isn + 1) & 0xFFFFFFFF          # next byte expected from the MSX
        self.isn = int.from_bytes(__import__('os').urandom(4), 'big')
        self.snd_una = self.snd_nxt = (self.isn + 1) & 0xFFFFFFFF
        self.out = b''                                    # sent to the MSX, not acknowledged
        self.pending = b''                                # from the host, not sent yet
        self.win = 1024
        self.fin_out = self.closed = False
        self.sent_at = 0.0
        self.lock = threading.Lock()
        self.sock = None

    def _send(self, seq, flags, data=b''):
        self.link._tcp_send(self.ip, self.msx_ip, self.port, self.msx_port, seq, self.rcv_nxt, flags, data)

    def open(self):
        host = '127.0.0.1' if self.ip == HOST_IP else socket.inet_ntoa(self.ip)
        try:
            self.sock = socket.create_connection((host, self.port), timeout=5)
            self.sock.settimeout(None)
        except OSError as e:
            self.link.log('ethnat: TCP to %s:%d refused: %s' % (host, self.port, e))
            self._send(0, 0x14)                           # RST + ACK
            self.closed = True
            return
        self.link.log('ethnat: TCP %d -> %s:%d' % (self.msx_port, host, self.port))
        self._send(self.isn, 0x12)                        # SYN + ACK
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        while not self.closed:
            try:
                data = self.sock.recv(4096)
            except OSError:
                data = b''
            with self.lock:
                if not data:
                    self.fin_out = True
                else:
                    self.pending += data
                self._push()
            if not data:
                return

    def _push(self):
        """Send what fits in the MSX's window (lock held)."""
        while self.pending and len(self.out) < self.win:
            n = min(self.MSS, self.win - len(self.out), len(self.pending))
            chunk, self.pending = self.pending[:n], self.pending[n:]
            self._send(self.snd_nxt, 0x18, chunk)         # PSH + ACK
            self.out += chunk
            self.snd_nxt = (self.snd_nxt + n) & 0xFFFFFFFF
            self.sent_at = time.monotonic()
        if self.fin_out and not self.pending and not self.out and not self.closed:
            self._send(self.snd_nxt, 0x11)                # FIN + ACK
            self.snd_nxt = (self.snd_nxt + 1) & 0xFFFFFFFF
            self.closed = True

    def on_segment(self, seq, ack, flags, win, data):
        with self.lock:
            self.win = max(win, 1)
            if flags & 0x10:                              # the MSX acknowledges
                done = (ack - self.snd_una) & 0xFFFFFFFF
                if 0 < done <= len(self.out):
                    self.out = self.out[done:]
                    self.snd_una = ack
            if data or flags & 1:
                if seq == self.rcv_nxt:
                    if data and self.sock:
                        try:
                            self.sock.sendall(data)
                        except OSError:
                            pass
                    self.rcv_nxt = (self.rcv_nxt + len(data) + (1 if flags & 1 else 0)) & 0xFFFFFFFF
                    if flags & 1 and self.sock:
                        try:
                            self.sock.shutdown(socket.SHUT_WR)
                        except OSError:
                            pass
                self._send(self.snd_nxt, 0x10)            # ACK (again, when out of order)
            self._push()

    def tick(self):
        with self.lock:
            if self.out and time.monotonic() - self.sent_at > 1.0:
                self._send(self.snd_una, 0x18, self.out[:self.MSS])
                self.sent_at = time.monotonic()

    def close(self):
        self.closed = True
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        with self.link.slock:
            self.link.tcp.pop(self.key, None)
