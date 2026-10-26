"""The real MSX LINK2 code (asm-common/include/link2.asm) on the lockstep wire.

Z80Msx has the interface of link2_sim.Msx (send, recv, MsxAborted), so every
server test and fault sweep can run against the assembled Z80 code instead of the
Python model: LINK2_MSX=z80 python -m unittest test_link2.  Port semantics are
those of the CPLD as the code uses them (design 8.3): OUT ($56) starts a read,
IN ($5A) returns it, OUT ($5A) writes, and in wait mode ($57 = 1) every IN/OUT of
$5A is one transfer.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import z80emu  # noqa: E402

INC = os.path.normpath(os.path.join(HERE, "..", "..", "..", "asm-common", "include"))
SJASMPLUS = os.environ.get("SJASMPLUS", r"C:\Users\roniv\Dev\bin\sjasmplus.exe")
_image = None


def assemble(extra=()):
    """(bytes at 0x0100, {symbol: address}) of link2_z80_test.asm."""
    with tempfile.TemporaryDirectory() as tmp:
        out, sym = os.path.join(tmp, "t.bin"), os.path.join(tmp, "t.sym")
        cmd = [SJASMPLUS, "--inc=" + INC, "--raw=" + out, "--sym=" + sym, *extra,
               os.path.join(HERE, "link2_z80_test.asm")]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode:
            raise RuntimeError("sjasmplus failed:\n" + r.stdout + r.stderr)
        symbols = {}
        for line in open(sym).read().splitlines():
            line = line.split(";")[0].strip()
            if ":" in line and "equ" in line.lower():
                name, rest = line.split(":", 1)
                symbols[name.strip()] = int(rest.lower().split("equ")[1].strip().lstrip("$").replace("0x", ""), 16)
        with open(out, "rb") as f:
            return f.read(), symbols


def image():
    global _image
    if _image is None:
        _image = assemble()
    return _image


class Ports:
    def __init__(self, wire, has_wait):
        self.w, self.has_wait = wire, has_wait
        self.latch = 0xFF
        self.wait = False
        self.xfers = 0

    def io_in(self, port):
        p = port & 0xFF
        if p == 0x56:
            return 0  # a transfer is complete as soon as it is started: the wire is a rendezvous
        if p == 0x5A:
            if self.wait:
                self.xfers += 1
                return self.w.msx_xfer(0)
            return self.latch
        if p == 0x57:
            return 0x0E | (0x80 if (self.wait and self.has_wait) else 0)
        if p == 0xA9:
            return 0xFF  # no key pressed
        return 0

    def io_out(self, port, v):
        p = port & 0xFF
        if p == 0x56:
            self.xfers += 1
            self.latch = self.w.msx_xfer(0)
        elif p == 0x5A:
            self.xfers += 1
            self.w.msx_xfer(v)
        elif p == 0x57:
            self.wait = bool(v & 1) and self.has_wait


class MsxAborted(Exception):
    pass


class Z80Msx:
    SRC_BURST, SRC_PLAIN = 0x8000, 0x6000  # outside page 1 / inside it

    def __init__(self, wire, size=8192, has_wait=True):
        from link2_sim import MsxAborted as _A
        self._A = _A
        code, self.sym = image()
        self.cpu = z80emu.Z80()
        self.cpu.mem[0x0100:0x0100 + len(code)] = code
        self.ports = Ports(wire, has_wait)
        self.cpu.io_in, self.cpu.io_out = self.ports.io_in, self.ports.io_out
        self.printed = bytearray()
        self.cpu.traps[self.sym["PRINT"]] = self._print
        self.size = size
        self.w = wire
        self.stats = {"retries": 0}
        self.t_states = 0

    def rd(self):  # the wire by hand, for tests that play one end themselves
        return self.w.msx_xfer(0)

    def wr(self, b):
        self.w.msx_xfer(b)

    def _print(self, cpu):
        a = cpu.hl
        while cpu.mem[a]:
            self.printed.append(cpu.mem[a])
            a += 1
        cpu.pc = cpu.pop()

    def _call(self, name, **regs):
        cpu = self.cpu
        cpu.sp = 0xF000
        cpu.f = 0
        t, _ = cpu.run_call(self.sym[name], **regs)
        self.t_states += t

    def _check(self):
        if self.cpu.f & 1:
            raise self._A("Z80 LINK2: A=%02X" % self.cpu.a)

    def send(self, data, may_burst=True):
        data = bytes(data)
        src = self.SRC_BURST if may_burst else self.SRC_PLAIN
        self.cpu.mem[src:src + len(data)] = data
        self._call("LINK_SEND_SIZE", hl=self.size, de=src, bc=len(data))
        self._check()

    def recv(self, maxbuf=65536, may_burst=True, at=None):
        buf = at if at is not None else (self.SRC_BURST if may_burst else self.SRC_PLAIN)
        self.cpu.mem[buf:buf + 0x6000] = bytes(0x6000)  # (no stale data from the last run)
        self._call("LINK_RECV", de=buf, bc=self.size, a=2)
        self._check()
        n = self.cpu.bc
        return bytes(self.cpu.mem[buf:buf + n])
