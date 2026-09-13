#!/usr/bin/env python3
"""End-to-end check of the Windows TAP path, without the MSX or openMSX.

Plays the part of the MSX: takes the TAP adapter, ARPs for the gateway,
answers the gateway's ARP for itself, then sends a real DNS query from
192.168.99.2 and waits for the answer to come back through the NAT.

A pass means the whole Windows side works - adapter, media status, forwarding,
WinNAT - and anything left is InterNestor Lite's configuration on the MSX.

    python test_wintap_nat.py [name-to-resolve]

Needs the OpenVPN TAP driver and msxpi-tcpip-setup.ps1 already run (as
Administrator). This script itself needs no special rights. Nothing else may
be holding the adapter - stop msxpi-server.py first.
"""
import os
import random
import struct
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "Server", "Python", "src"))
import msxpi_eth as E                                    # noqa: E402

GATEWAY = "192.168.99.1"
MSX_IP = "192.168.99.2"
QUERY = sys.argv[1] if len(sys.argv) > 1 else "google.com"


def ip_bytes(text):
    return bytes(int(p) for p in text.split("."))


def checksum(data):
    if len(data) % 2:
        data += b"\x00"
    total = 0
    for i in range(0, len(data), 2):
        total += (data[i] << 8) | data[i + 1]
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def arp(op, sender_mac, sender_ip, target_mac, target_ip, dst_mac):
    return (dst_mac + sender_mac + b"\x08\x06"
            + struct.pack(">HHBBH", 1, 0x0800, 6, 4, op)
            + sender_mac + ip_bytes(sender_ip)
            + target_mac + ip_bytes(target_ip))


def dns_query(name, txid):
    q = b""
    for label in name.split("."):
        q += bytes([len(label)]) + label.encode()
    q += b"\x00"
    return (struct.pack(">HHHHHH", txid, 0x0100, 1, 0, 0, 0)
            + q + struct.pack(">HH", 1, 1))


def udp_packet(src_ip, dst_ip, src_port, dst_port, payload):
    # UDP checksum is optional over IPv4 and zero means "not computed", which
    # keeps this short without weakening the test: the IP header checksum below
    # is what routers actually verify.
    udp = struct.pack(">HHHH", src_port, dst_port, 8 + len(payload), 0) + payload
    total = 20 + len(udp)
    hdr = struct.pack(">BBHHHBBH4s4s", 0x45, 0, total, random.randint(0, 0xFFFF),
                      0, 64, 17, 0, ip_bytes(src_ip), ip_bytes(dst_ip))
    hdr = hdr[:10] + struct.pack(">H", checksum(hdr)) + hdr[12:]
    return hdr + udp


def parse_a_records(payload):
    """Just enough DNS to pull the A records out of an answer."""
    qd, an = struct.unpack(">HH", payload[4:8])
    pos = 12
    for _ in range(qd):
        while payload[pos]:
            pos += payload[pos] + 1
        pos += 5
    out = []
    for _ in range(an):
        if payload[pos] & 0xC0 == 0xC0:
            pos += 2
        else:
            while payload[pos]:
                pos += payload[pos] + 1
            pos += 1
        rtype, _, _, rdlen = struct.unpack(">HHIH", payload[pos:pos + 10])
        pos += 10
        if rtype == 1 and rdlen == 4:
            out.append(".".join(str(b) for b in payload[pos:pos + 4]))
        pos += rdlen
    return out


def main():
    dns_server = None
    for line in os.popen("netsh interface ipv4 show dnsservers").read().splitlines():
        parts = line.split()
        if parts and parts[-1].count(".") == 3 and not parts[-1].startswith("0."):
            dns_server = parts[-1]
            break
    dns_server = dns_server or "1.1.1.1"
    print("resolver: %s   asking for: %s" % (dns_server, QUERY))

    link = E.make_link(log=print)
    if not isinstance(link, E.WinTapLink):
        raise SystemExit("FAIL: no TAP link (%s) - is the driver installed and "
                         "the adapter free?" % type(link).__name__)
    print("adapter: %s" % link.ifname)

    try:
        # 1. Who is the gateway?
        # Retried, not sent once: setting the media status to "connected" is
        # what makes Windows attach the address to this interface, and it is
        # not instant - a single request sent the moment the handle opens is
        # simply dropped, and the test then blames the configuration.
        next_arp = 0.0
        gw_mac = None
        txid = random.randint(0, 0xFFFF)
        sent_query = False
        answers = []
        deadline = time.time() + 15

        while time.time() < deadline:
            if gw_mac is None and time.time() >= next_arp:
                link.transmit(arp(1, link.mac, MSX_IP, b"\x00" * 6, GATEWAY,
                                  b"\xff" * 6))
                next_arp = time.time() + 1.0
            if not link.pending():
                time.sleep(0.02)
                continue
            frame, _ = link.pop()
            if len(frame) < 14:
                continue
            etype = (frame[12] << 8) | frame[13]

            if etype == 0x0806 and len(frame) >= 42:
                op = (frame[20] << 8) | frame[21]
                if op == 2 and gw_mac is None:          # reply to our request
                    gw_mac = frame[22:28]
                    print("gateway %s is at %s" %
                          (GATEWAY, ":".join("%02x" % b for b in gw_mac)))
                elif op == 1 and frame[38:42] == ip_bytes(MSX_IP):
                    # Windows asking where the MSX is; answer or the reply
                    # can never be delivered back to us.
                    link.transmit(arp(2, link.mac, MSX_IP, frame[22:28],
                                      ".".join(str(b) for b in frame[28:32]),
                                      frame[22:28]))

            elif etype == 0x0800 and len(frame) >= 34:
                ihl = (frame[14] & 0x0F) * 4
                if frame[14 + 9] == 17:                 # UDP
                    udp = frame[14 + ihl:]
                    sport = (udp[0] << 8) | udp[1]
                    if sport == 53:
                        payload = udp[8:]
                        if struct.unpack(">H", payload[:2])[0] == txid:
                            answers = parse_a_records(payload)
                            break

            if gw_mac and not sent_query:
                pkt = udp_packet(MSX_IP, dns_server, 5353, 53,
                                 dns_query(QUERY, txid))
                link.transmit(gw_mac + link.mac + b"\x08\x00" + pkt)
                sent_query = True
                print("DNS query sent from %s" % MSX_IP)

        if answers:
            print("PASS: %s resolved to %s" % (QUERY, ", ".join(answers)))
            print("      NAT, forwarding and the TAP link all work.")
            return 0
        if not gw_mac:
            print("FAIL: no ARP reply from %s - is the address assigned? "
                  "(run msxpi-tcpip-setup.ps1 as Administrator)" % GATEWAY)
        else:
            print("FAIL: no DNS answer came back. The link works (the gateway "
                  "answered ARP), so this is NAT, forwarding or the firewall.")
        return 1
    finally:
        link.close()


if __name__ == "__main__":
    sys.exit(main())
