"""The assembled Ethernet UNAPI driver (UNAPI/src/ethrom.asm, protocol 2 and the
ETH_V3 build, protocol 3) against msxpi_eth.EthShuttle, byte for byte on the
lockstep wire.

The driver's own routines (ETH_VERIFY, FN_IN_STATUS, FN_GET_FRAME, FN_SEND_FRAME)
run on the Z80 interpreter with IX at a work area, in hardware /WAIT mode and in
the polled mode.  The Pi end is the real shuttle on a thread, with the transport
callables the server gives it: for protocol 3 the burst callables carry the GO
byte inside the run.  Every wire byte is logged, so the tests can say where the
GO bytes are.

    python -m unittest test_eth3_z80
"""
import os
import subprocess
import sys
import tempfile
import threading
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "src"))
import link2_sim as S  # noqa: E402
import msxpi_eth as eth  # noqa: E402
import z80emu  # noqa: E402

UNAPI = os.path.normpath(os.path.join(HERE, "..", "..", "..", "UNAPI", "src"))
SJASMPLUS = os.environ.get("SJASMPLUS", r"C:\Users\roniv\Dev\bin\sjasmplus.exe")
WRK = 0xC000
MODE_POLL, MODE_WAIT = 0, 1
_images = {}


def build(version):
    """(code, org, symbols) of the ROM driver; version 3 is ethrom3.asm."""
    if version not in _images:
        src = os.path.join(UNAPI, "ethrom3.asm" if version == 3 else "ethrom.asm")
        with tempfile.TemporaryDirectory() as tmp:
            out, sym = os.path.join(tmp, "e.bin"), os.path.join(tmp, "e.sym")
            r = subprocess.run([SJASMPLUS, "--raw=" + out, "--sym=" + sym, src],
                               capture_output=True, text=True)
            if r.returncode:
                raise RuntimeError(r.stdout + r.stderr)
            symbols = {}
            for line in open(sym).read().splitlines():
                if ": EQU " in line:
                    name, val = line.split(": EQU ")
                    symbols[name.strip()] = int(val.split()[0], 16)
            _images[version] = (open(out, "rb").read(), symbols["UNAPI_ORG3" if version == 3 else "UNAPI_ORG"], symbols)
    return _images[version]


class Ports:
    """The CPLD as the driver uses it (the same rendezvous model as z80_msx.Ports)."""

    def __init__(self, wire, has_wait=True):
        self.w, self.has_wait = wire, has_wait
        self.latch = 0xFF
        self.wait = False

    def io_in(self, port):
        p = port & 0xFF
        if p == 0x56:
            return 0
        if p == 0x5A:
            return self.w.msx_xfer(0) if self.wait else self.latch
        if p == 0x57:
            return 0x0E | (0x80 if (self.wait and self.has_wait) else 0)
        return 0

    def io_out(self, port, v):
        p = port & 0xFF
        if p == 0x56:
            self.latch = self.w.msx_xfer(0)
        elif p == 0x5A:
            self.w.msx_xfer(v)
        elif p == 0x57:
            self.wait = bool(v & 1) and self.has_wait


def pi_shuttle(wire, link, kept=None):
    """The shuttle with the transport callables of msxpi_ethglue, on the wire."""
    def rb():
        return 0, wire.pi_xfer(0)

    def wb(v):
        wire.pi_xfer(v)
        return 0

    def burst(data):
        for b in data:
            wire.pi_xfer(b)
        return 0

    def rburst(n):
        return bytes(wire.pi_xfer(0) for _ in range(n))

    def burst_go(data):
        return burst(bytes([eth.ETH_GO]) + bytes(data))

    def rburst_go(n):
        wire.pi_xfer(eth.ETH_GO)
        return rburst(n)

    return eth.EthShuttle(link, rb, wb, write_burst=burst, read_burst=rburst,
                          write_burst_go=burst_go, read_burst_go=rburst_go,
                          load_proto=None if kept is None else (lambda: kept.get('v')),
                          save_proto=None if kept is None else (lambda v: kept.__setitem__('v', v)))


class Rig:
    def __init__(self, version, mode):
        self.version = version
        self.link = eth.MockLink()
        self.wire = S.Wire(timeout=2.0)
        self.wire.trace = True
        self.sh = pi_shuttle(self.wire, self.link)
        self.code, org, self.sym = build(version)
        self.cpu = z80emu.Z80()
        self.cpu.mem[org:org + len(self.code)] = self.code
        self.ports = Ports(self.wire, mode == MODE_WAIT)
        self.cpu.io_in, self.cpu.io_out = self.ports.io_in, self.ports.io_out
        self.cpu.mem[WRK + self.sym["o_ETH_MODE"]] = mode
        self.t = threading.Thread(target=self._pi, daemon=True)
        self.t.start()

    def _pi(self):
        try:
            while True:
                op = self.wire.pi_xfer(0)
                self.sh.handle(op)
        except S.Hung:
            pass

    def call(self, name, **regs):
        self.cpu.sp = 0xF000
        self.cpu.f = 0
        self.cpu.run_call(self.sym[name], ix=WRK, **regs)
        return self.cpu

    def close(self):
        self.wire.close()
        self.t.join(3)

    def transfers(self, start=0):
        """(Pi byte, MSX byte) of every transfer since log entry `start`."""
        log = self.wire.log[start:]
        return list(zip([b for d, b in log if d == "p2m"], [b for d, b in log if d == "m2p"]))


def frame(n, fill=0x41):
    return bytes(range(14)) + bytes([fill]) * (n - 14)


class DriverAgainstShuttle(unittest.TestCase):
    def rigs(self):
        for version in (2, 3):
            for mode in (MODE_WAIT, MODE_POLL):
                rig = Rig(version, mode)
                self.addCleanup(rig.close)
                yield version, mode, rig

    def test_verify_selects_the_protocol(self):
        for version, mode, rig in self.rigs():
            cpu = rig.call("ETH_VERIFY")
            self.assertEqual(cpu.f & 1, 0, (version, mode))
            self.assertEqual(rig.sh.proto, version, (version, mode))
            # the probe is the first thing on the wire: opcode, then the reply
            xfers = rig.transfers()
            self.assertEqual(xfers[0][1], 0xCA if version == 3 else 0xC0)
            p2m = [p for p, _ in xfers[1:]]
            if version == 3:
                self.assertEqual(p2m[:2], [eth.ETH_GO, eth.ETH_RC_OK3])
            else:
                self.assertEqual(p2m[0], eth.ETH_RC_OK)

    def test_in_status_and_get_frame(self):
        for version, mode, rig in self.rigs():
            rig.call("ETH_VERIFY")
            cpu = rig.call("FN_IN_STATUS")
            self.assertEqual(cpu.a, 0, (version, mode))
            for n in (67, 600):
                f = frame(n, fill=n & 0xFF)
                rig.link.inject(f)
                cpu = rig.call("FN_IN_STATUS")
                self.assertEqual((cpu.a, cpu.bc), (1, n), (version, mode, n))
                cpu = rig.call("FN_GET_FRAME", hl=0x9000)
                self.assertEqual((cpu.a, cpu.bc), (0, n), (version, mode, n))
                self.assertEqual(bytes(cpu.mem[0x9000:0x9000 + n]), f, (version, mode, n))
            cpu = rig.call("FN_GET_FRAME", hl=0x9000)
            self.assertEqual(cpu.a, 1, (version, mode))    # none waiting

    def test_send_frame(self):
        for version, mode, rig in self.rigs():
            rig.call("ETH_VERIFY")
            for n in (16, 255, 256, 257, 1514):
                f = frame(n, fill=n & 0xFF)
                rig.cpu.mem[0x9000:0x9000 + n] = f
                rig.link.sent = []
                cpu = rig.call("FN_SEND_FRAME", hl=0x9000, bc=n, d=0)
                self.assertEqual(cpu.a, 0, (version, mode, n))
                self.assertEqual(rig.link.sent[0][:n], f, (version, mode, n))

    def test_a_bad_checksum_is_refused(self):
        for version, mode, rig in self.rigs():
            rig.call("ETH_VERIFY")
            n = 64
            rig.cpu.mem[0x9000:0x9000 + n] = frame(n)
            real = rig.sh._op_send_frame

            def corrupt(real=real, rig=rig):
                # the Pi sees one byte of the frame changed on the wire
                rig.wire.flip("m2p", rig.wire.n["m2p"] + 5, 0x01)
                real()
            rig.sh._dispatch[eth.OP_SEND_FRAME] = corrupt
            rig.link.sent = []
            cpu = rig.call("FN_SEND_FRAME", hl=0x9000, bc=n, d=0)
            self.assertNotEqual(cpu.a, 0, (version, mode))
            self.assertEqual(rig.link.sent, [], (version, mode))

    def test_protocol_3_puts_a_go_byte_before_every_burst(self):
        rig = Rig(3, MODE_WAIT)
        self.addCleanup(rig.close)
        rig.call("ETH_VERIFY")
        before = len(rig.wire.log)
        rig.call("FN_IN_STATUS")
        x = rig.transfers(before)
        # the opcode, then the reply burst: GO first, then the five bytes
        self.assertEqual((x[0][1], [p for p, _ in x[1:]]), (0xC5, [eth.ETH_GO] + [0] * 5))

    def test_protocol_2_has_no_go_byte(self):
        rig = Rig(2, MODE_WAIT)
        self.addCleanup(rig.close)
        rig.call("ETH_VERIFY")
        before = len(rig.wire.log)
        rig.call("FN_IN_STATUS")
        x = rig.transfers(before)
        self.assertEqual((x[0][1], [p for p, _ in x[1:]]), (0xC5, [0] * 5))

    def test_a_refused_length_is_not_sent_into_the_opcode_hunt(self):
        # The Pi answers the length with BADLEN instead of GO (as for a length damaged
        # on the wire).  Protocol 3 checks GO, so the frame is never sent with OTIR:
        # sent, its bytes would be read as opcodes (here 0xC8, OP_RESET).
        for mode in (MODE_WAIT, MODE_POLL):
            rig = Rig(3, mode)
            self.addCleanup(rig.close)
            rig.call("ETH_VERIFY")

            def refuse(rig=rig):
                rig.sh._read_n(2)
                rig.sh._write(eth.ETH_RC_BADLEN)
            rig.sh._dispatch[eth.OP_SEND_FRAME] = refuse
            n = 64
            rig.cpu.mem[0x9000:0x9000 + n] = frame(n, fill=eth.OP_RESET)
            before = len(rig.wire.log)
            cpu = rig.call("FN_SEND_FRAME", hl=0x9000, bc=n, d=0)
            self.assertNotEqual(cpu.a, 0, mode)
            self.assertNotIn(eth.OP_RESET, [m for _, m in rig.transfers(before)], mode)
            # and the link still works
            rig.sh._dispatch[eth.OP_SEND_FRAME] = rig.sh._op_send_frame
            rig.link.sent = []
            cpu = rig.call("FN_SEND_FRAME", hl=0x9000, bc=n, d=0)
            self.assertEqual(cpu.a, 0, mode)

    def test_protocol_3_survives_a_server_restart(self):
        # The driver probes only when it starts; a restarted server must still serve 3.
        for kept, works in (({}, True), (None, False)):     # {}: ETHPROTO in msxpi.ini
            rig = Rig(3, MODE_WAIT)
            self.addCleanup(rig.close)
            rig.sh = pi_shuttle(rig.wire, rig.link, kept)
            rig.call("ETH_VERIFY")
            rig.sh = pi_shuttle(rig.wire, rig.link, kept)     # the restart
            rig.link.inject(frame(67))
            cpu = rig.call("FN_IN_STATUS")
            self.assertEqual((cpu.a, cpu.bc) == (1, 67), works, kept)

if __name__ == "__main__":
    unittest.main()
