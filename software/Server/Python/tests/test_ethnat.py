"""msxpi_ethnat.UdpNatLink: ARP, UDP both ways through a host socket on the same port, ICMP echo to the host."""
import socket
import struct
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_ethnat as nat
from test_netplay import free_ports, wait_for

MSX_MAC = b'\x02\x4d\x53\x58\x50\x69'
MSX_IP = bytes([10, 0, 2, 15])


def ip_frame(proto, dst, payload):
    hdr = struct.pack('!BBHHHBBH4s4s', 0x45, 0, 20 + len(payload), 1, 0, 64, proto, 0, MSX_IP, dst)
    hdr = hdr[:10] + struct.pack('!H', nat.checksum(hdr)) + hdr[12:]
    return nat.HOST_MAC + MSX_MAC + b'\x08\x00' + hdr + payload


def udp(sport, dport, data):
    return struct.pack('!HHHH', sport, dport, 8 + len(data), 0) + data


class UdpNat(unittest.TestCase):
    def setUp(self):
        self.link = nat.UdpNatLink()

    def tearDown(self):
        self.link.close()

    def frames(self):
        out = []
        while True:
            f, _ = self.link.pop()
            if f is None:
                return out
            out.append(f)

    def test_arp_is_answered_for_the_host(self):
        req = struct.pack('!HHBBH', 1, 0x0800, 6, 4, 1) + MSX_MAC + MSX_IP + b'\x00' * 6 + nat.HOST_IP
        self.link.transmit(nat.BROADCAST + MSX_MAC + b'\x08\x06' + req)
        (f,) = self.frames()
        self.assertEqual(f[:6], MSX_MAC)
        self.assertEqual(f[20:22], b'\x00\x02')                       # reply
        self.assertEqual(f[22:28], nat.HOST_MAC)
        self.assertEqual(f[28:32], nat.HOST_IP)

    def test_udp_out_to_localhost_and_back(self):
        mport, pport = free_ports(2)
        peer = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        peer.bind(('127.0.0.1', pport))
        peer.settimeout(2)
        self.link.transmit(ip_frame(17, nat.HOST_IP, udp(mport, pport, b'hello')))
        data, addr = peer.recvfrom(100)
        self.assertEqual((data, addr[1]), (b'hello', mport))         # the same port number on the host
        peer.sendto(b'world', ('127.0.0.1', mport))
        self.assertTrue(wait_for(lambda: self.link.pending() > 0, 2))
        (f,) = self.frames()
        ip = f[14:]
        self.assertEqual(nat.checksum(ip[:20]), 0)                   # a valid IP header
        self.assertEqual((ip[12:16], ip[16:20]), (nat.HOST_IP, MSX_IP))
        u = ip[20:20 + 13]
        self.assertEqual(struct.unpack('!HH', u[:4]), (pport, mport))
        self.assertEqual(u[8:], b'world')
        pseudo = nat.HOST_IP + MSX_IP + struct.pack('!BBH', 0, 17, len(u))
        self.assertEqual(nat.checksum(pseudo + u), 0)                # and a valid UDP checksum
        peer.close()

    def test_ping_the_host(self):
        echo = b'\x08\x00\x00\x00\x12\x34\x00\x01abcd'
        echo = echo[:2] + struct.pack('!H', nat.checksum(echo)) + echo[4:]
        self.link.transmit(ip_frame(1, nat.HOST_IP, echo))
        (f,) = self.frames()
        icmp = f[34:34 + len(echo)]
        self.assertEqual(icmp[0], 0)                                  # echo reply
        self.assertEqual(icmp[4:], echo[4:])
        self.assertEqual(nat.checksum(icmp), 0)


if __name__ == '__main__':
    unittest.main()
