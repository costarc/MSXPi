"""msxpi_eth.EthShuttle, protocols 2 and 3: the probe version, ETH_IN_STATUS with a frame
inline, ETH_GET_FRAME's discard (maxlen 0) and ETH_SEND_FRAME's burst receive.

The shuttle is driven through fake transport callables, so this runs anywhere
without a Pi or an MSX - the byte layouts here are what ethops.asm reads."""
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_eth as eth


class Wire(object):
    """The MSX end of the link: bytes it sends, bytes it got back, and how."""

    def __init__(self, to_pi=b''):
        self.to_pi = bytearray(to_pi)
        self.out = bytearray()
        self.bursts_in = []          # sizes read with read_burst

    def read_byte(self):
        if not self.to_pi:
            return (1, None)
        return (0, self.to_pi.pop(0))

    def read_burst(self, n):
        self.bursts_in.append(n)
        if len(self.to_pi) < n:
            return None
        data = bytes(self.to_pi[:n])
        del self.to_pi[:n]
        return data

    def write_byte(self, v):
        self.out.append(v)
        return 0

    def write_burst(self, data):
        self.out.extend(data)
        return 0


def frame(n, fill=0x41):
    return bytes(range(14)) + bytes([fill]) * (n - 14)


class Shuttle(unittest.TestCase):
    def setUp(self):
        self.link = eth.MockLink()

    def run_op(self, opcode, to_pi=b''):
        wire = Wire(to_pi)
        sh = eth.EthShuttle(self.link, wire.read_byte, wire.write_byte,
                            write_burst=wire.write_burst,
                            read_burst=wire.read_burst)
        self.assertTrue(sh.handle(opcode))
        return wire

    def test_probe_reports_protocol_2(self):
        w = self.run_op(eth.OP_PROBE)
        self.assertEqual(bytes(w.out), b'\x00ETH\x02')

    def test_in_status_empty(self):
        w = self.run_op(eth.OP_IN_STATUS)
        self.assertEqual(bytes(w.out), bytes(5))

    def test_in_status_sends_a_small_frame_inline_and_dequeues_it(self):
        f = frame(67)
        self.link.inject(f)
        w = self.run_op(eth.OP_IN_STATUS)
        self.assertEqual(w.out[0], eth.IN_INLINE)
        self.assertEqual(w.out[1] | (w.out[2] << 8), 67)
        self.assertEqual(bytes(w.out[3:5]), f[12:14])
        self.assertEqual(bytes(w.out[5:5 + 67]), f)
        self.assertEqual(w.out[5 + 67], sum(f) & 0xFF)
        self.assertEqual(len(w.out), 5 + 67 + 1)
        self.assertEqual(self.link.pending(), 0)

    def test_inline_boundary(self):
        self.link.inject(frame(eth.RX_INLINE_MAX))
        w = self.run_op(eth.OP_IN_STATUS)
        self.assertEqual(w.out[0], eth.IN_INLINE)
        self.link.inject(frame(eth.RX_INLINE_MAX + 1))
        w = self.run_op(eth.OP_IN_STATUS)
        self.assertEqual(w.out[0], eth.IN_WAIT)
        self.assertEqual(len(w.out), 5)
        self.assertEqual(self.link.pending(), 1)      # still queued for GET_FRAME

    def test_short_frames_are_padded_before_the_length_is_reported(self):
        self.link.inject(frame(42))
        w = self.run_op(eth.OP_IN_STATUS)
        self.assertEqual(w.out[1] | (w.out[2] << 8), eth.RX_PAD_TO)
        self.assertEqual(len(w.out), 5 + eth.RX_PAD_TO + 1)

    def test_get_frame_unchanged_for_large_frames(self):
        f = frame(600)
        self.link.inject(f)
        w = self.run_op(eth.OP_GET_FRAME, bytes([1514 & 0xFF, 1514 >> 8]))
        self.assertEqual(bytes(w.out[:3]), bytes([600 & 0xFF, 600 >> 8, 0]))
        self.assertEqual(bytes(w.out[3:603]), f)
        self.assertEqual(w.out[603], sum(f) & 0xFF)

    def test_get_frame_maxlen_0_discards_without_sending_it(self):
        self.link.inject(frame(600))
        self.link.inject(frame(70))
        w = self.run_op(eth.OP_GET_FRAME, b'\x00\x00')
        self.assertEqual(bytes(w.out), bytes([600 & 0xFF, 600 >> 8, eth.FLAG_MORE_PENDING]))
        self.assertEqual(self.link.pending(), 1)

    def test_send_frame_payload_and_checksum_arrive_as_one_burst(self):
        for n in (16, 64, 255, 256, 257, 512, 1514):
            f = frame(n, fill=n & 0xFF)
            self.link.sent = []
            w = self.run_op(eth.OP_SEND_FRAME,
                            bytes([n & 0xFF, n >> 8]) + f + bytes([sum(f) & 0xFF]))
            self.assertEqual(w.bursts_in, [n + 1], n)
            self.assertEqual(bytes(w.out), bytes([eth.ETH_RC_OK]), n)
            self.assertEqual(self.link.sent[0][:n], f, n)

    def test_send_frame_bad_checksum(self):
        f = frame(64)
        w = self.run_op(eth.OP_SEND_FRAME, bytes([64, 0]) + f + bytes([(sum(f) + 1) & 0xFF]))
        self.assertEqual(bytes(w.out), bytes([eth.ETH_RC_CHKSUM]))
        self.assertEqual(self.link.sent, [])

    def test_send_frame_without_burst_reader_falls_back_to_bytes(self):
        f = frame(64)
        wire = Wire(bytes([64, 0]) + f + bytes([sum(f) & 0xFF]))
        sh = eth.EthShuttle(self.link, wire.read_byte, wire.write_byte,
                            write_burst=wire.write_burst)
        sh.handle(eth.OP_SEND_FRAME)
        self.assertEqual(bytes(wire.out), bytes([eth.ETH_RC_OK]))


class Wire3(Wire):
    """The same, with the GO-carrying burst callables of protocol 3."""

    def __init__(self, to_pi=b''):
        Wire.__init__(self, to_pi)
        self.go_bursts_out = []      # replies sent as GO + data in one run
        self.go_bursts_in = []       # sizes taken after a GO

    def write_burst_go(self, data):
        self.go_bursts_out.append(bytes(data))
        self.out.extend(bytes([eth.ETH_GO]) + data)
        return 0

    def read_burst_go(self, n):
        self.go_bursts_in.append(n)
        return Wire.read_burst(self, n)


class Protocol3(unittest.TestCase):
    OK = eth.ETH_RC_OK3

    def setUp(self):
        self.link = eth.MockLink()
        self.wire = Wire3()
        self.sh = eth.EthShuttle(self.link, self.wire.read_byte, self.wire.write_byte,
                                 write_burst=self.wire.write_burst,
                                 read_burst=self.wire.read_burst,
                                 write_burst_go=self.wire.write_burst_go,
                                 read_burst_go=self.wire.read_burst_go)

    def op(self, opcode, to_pi=b''):
        self.wire.to_pi.extend(to_pi)
        self.wire.out.clear()
        self.assertTrue(self.sh.handle(opcode))
        return bytes(self.wire.out)

    def test_probe3_reports_protocol_3_with_go_and_rc_5a(self):
        self.assertEqual(self.op(eth.OP_PROBE3), bytes([eth.ETH_GO, self.OK]) + b'ETH\x03')

    def test_a_v2_probe_switches_back(self):
        self.op(eth.OP_PROBE3)
        self.assertEqual(self.op(eth.OP_PROBE), b'\x00ETH\x02')
        self.assertEqual(self.op(eth.OP_GET_NETSTAT)[0], 0)

    def test_replies_are_one_go_burst_with_rc_5a(self):
        self.op(eth.OP_PROBE3)
        out = self.op(eth.OP_GET_HWADD)
        self.assertEqual(out, bytes([eth.ETH_GO, self.OK]) + self.link.mac)
        self.assertEqual(self.op(eth.OP_FILTERS, bytes([0x80])),
                         bytes([eth.ETH_GO, self.OK, self.link.filters]))
        self.assertEqual(self.op(eth.OP_RESET)[:2], bytes([eth.ETH_GO, self.OK]))

    def test_in_status_and_get_frame_start_with_go(self):
        self.op(eth.OP_PROBE3)
        self.assertEqual(self.op(eth.OP_IN_STATUS), bytes([eth.ETH_GO]) + bytes(5))
        f = frame(600)
        self.link.inject(f)
        out = self.op(eth.OP_GET_FRAME, bytes([1514 & 0xFF, 1514 >> 8]))
        self.assertEqual(out[0], eth.ETH_GO)
        self.assertEqual(out[1:4], bytes([600 & 0xFF, 600 >> 8, 0]))
        self.assertEqual(out[4:604], f)
        self.assertEqual(len(self.wire.go_bursts_out), 3)    # probe, status, frame: one run each

    def test_send_frame_payload_follows_a_go_and_the_result_is_rc_5a(self):
        self.op(eth.OP_PROBE3)
        for n in (16, 257, 1514):
            f = frame(n, fill=n & 0xFF)
            self.wire.go_bursts_in.clear()
            out = self.op(eth.OP_SEND_FRAME, bytes([n & 0xFF, n >> 8]) + f + bytes([sum(f) & 0xFF]))
            self.assertEqual(self.wire.go_bursts_in, [n + 1], n)
            self.assertEqual(out, bytes([self.OK]), n)

    def test_without_go_burst_callables_the_go_byte_is_written_plainly(self):
        wire = Wire()
        sh = eth.EthShuttle(self.link, wire.read_byte, wire.write_byte,
                            write_burst=wire.write_burst, read_burst=wire.read_burst)
        sh.handle(eth.OP_PROBE3)
        self.assertEqual(bytes(wire.out), bytes([eth.ETH_GO, self.OK]) + b'ETH\x03')
        f = frame(64)
        wire.out.clear()
        wire.to_pi.extend(bytes([64, 0]) + f + bytes([sum(f) & 0xFF]))
        sh.handle(eth.OP_SEND_FRAME)
        self.assertEqual(bytes(wire.out), bytes([eth.ETH_GO, self.OK]))

    def test_the_protocol_is_kept_across_a_restart(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            keep = os.path.join(tmp, 'eth_proto')

            def shuttle():
                return eth.EthShuttle(self.link, self.wire.read_byte, self.wire.write_byte,
                                      write_burst_go=self.wire.write_burst_go,
                                      read_burst_go=self.wire.read_burst_go,
                                      proto_file=keep)
            self.assertEqual(shuttle().proto, 2)           # no file yet
            shuttle().handle(eth.OP_PROBE3)
            self.assertEqual(shuttle().proto, 3)
            shuttle().handle(eth.OP_PROBE)
            self.assertEqual(shuttle().proto, 2)


if __name__ == '__main__':
    unittest.main()
