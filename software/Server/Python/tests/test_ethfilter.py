"""msxpi_eth.BaseLink's LAN filter (plan D5): on a real LAN only the frames the MSX would use reach its queue."""
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_eth as eth

MAC = b"\x02\x4d\x53\x58\x50\x69"
OTHER = b"\x00\x11\x22\x33\x44\x55"
BCAST = b"\xff" * 6
MSX_IP = bytes([192, 168, 1, 50])


def arp_request(target_ip, sender_mac=OTHER, dst=BCAST):
    return (dst + sender_mac + b"\x08\x06" + struct.pack(">HHBBH", 1, 0x0800, 6, 4, 1) + sender_mac + bytes([192, 168, 1, 7])
            + b"\0" * 6 + target_ip)


def udp(dst_mac, dport, src_mac=OTHER):
    ip = bytes([0x45, 0, 0, 40, 0, 0, 0, 0, 64, 17, 0, 0]) + bytes([192, 168, 1, 7]) + bytes([192, 168, 1, 255])
    return dst_mac + src_mac + b"\x08\x00" + ip + struct.pack(">HHHH", 1234, dport, 8, 0) + b"\0" * 8


class LanFilter(unittest.TestCase):
    def link(self, active=True):
        link = eth.BaseLink()
        link.lan_filter, link.lan_filter_active = True, active
        return link

    def test_own_mac_passes_other_unicast_does_not(self):
        link = self.link()
        link._push(udp(MAC, 9000))
        link._push(udp(OTHER, 9000))
        self.assertEqual((link.pending(), link.filtered), (1, 1))

    def test_multicast_and_foreign_broadcasts_are_dropped(self):
        link = self.link()
        link._push(udp(b"\x01\x00\x5e\x00\x00\xfb", 5353))      # mDNS
        link._push(udp(BCAST, 137))                              # NetBIOS
        self.assertEqual((link.pending(), link.filtered), (0, 2))

    def test_dhcp_broadcast_passes(self):
        link = self.link()
        link._push(udp(BCAST, 68))
        self.assertEqual(link.pending(), 1)

    def test_arp_only_for_the_msx_ip_once_it_is_known(self):
        link = self.link()
        link._push(arp_request(bytes([192, 168, 1, 99])))        # IP not known yet: let it through
        self.assertEqual(link.pending(), 1)
        mine = arp_request(MSX_IP, sender_mac=MAC, dst=OTHER)    # the MSX's own ARP: learn its address
        link.learn(mine)
        self.assertEqual(link.msx_ip, bytes([192, 168, 1, 7]))   # (sender protocol address field)
        link.msx_ip = MSX_IP
        link._push(arp_request(bytes([192, 168, 1, 99])))
        link._push(arp_request(MSX_IP))
        self.assertEqual((link.pending(), link.filtered), (2, 1))

    def test_ip_source_of_a_sent_frame_is_learned(self):
        link = self.link()
        ip = bytes([0x45, 0, 0, 40, 0, 0, 0, 0, 64, 17, 0, 0]) + MSX_IP + bytes([10, 0, 0, 1])
        link.learn(OTHER + MAC + b"\x08\x00" + ip + b"\0" * 20)
        self.assertEqual(link.msx_ip, MSX_IP)

    def test_promiscuous_and_no_broadcast_bits(self):
        link = self.link()
        link.filters = 0x10
        link._push(udp(OTHER, 9000))
        self.assertEqual(link.pending(), 1)
        link.filters = 0x02                                      # broadcasts not accepted
        link._push(udp(BCAST, 68))
        self.assertEqual(link.filtered, 1)

    def test_links_without_the_filter_are_untouched(self):
        link = self.link(active=False)                           # the user-mode NAT and mock links
        link._push(udp(OTHER, 9000))
        self.assertEqual((link.pending(), link.filtered), (1, 0))


if __name__ == '__main__':
    unittest.main()
