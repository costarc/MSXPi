"""T3: the assembled MSX LINK2 code against the Python reference model, byte for byte.

The same server steps run once with link2_sim.ModelMsx and once with the Z80 code
(z80_msx.Z80Msx) over the lockstep wire.  Every byte that crosses the wire, in both
directions and in order, must be identical, and so must the outcome (the data, or
that the MSX gave up).  That covers the cases of design section 8 as the server
drives them: clean transfers in both directions, burst and polled, single-block and
multi-block, bit flips and slips at chosen positions (NAK, ABORT, duplicates, the
doubled final answer, the end mark, the ABORT flood).

    python -m unittest test_link2_z80          (about 5 minutes)
"""
import binascii
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import link2_sim as S
import msxpi_blocks as B
import z80_msx
from test_link2 import pattern


def trace(cls, direction, data, size=8192, has_wait=True, pi_burst=True, may_burst=True,
          flips=(), slips=(), follow=True):
    """(wire log, outcome) of one transfer (and a clean follow-up) with the given MSX."""
    w = S.Wire(timeout=2.0)
    w.trace = True
    for d, i, mask in flips:
        w.flip(d, i, mask)
    for k in slips:
        w.slip(k)
    results = []
    if direction == "msx2pi":
        def loop():
            while True:
                results.append(B.link_recv(65536))
        steps = [loop]
    else:
        def follow_loop():
            while True:
                results.append(B.link_send(pattern(300, 99)))
        steps = [lambda: results.append(B.link_send(data) if data else None), follow_loop]
    srv = S.Server(w, steps, pi_burst).start()
    m = cls(w, size, has_wait)
    outcome = []
    for payload in ([data] + ([pattern(300, 99)] if follow else [])):
        try:
            if direction == "msx2pi":
                m.send(payload, may_burst)
                outcome.append("sent")
            else:
                outcome.append(bytes(m.recv(may_burst=may_burst)))
        except S.MsxAborted:
            outcome.append("aborted")
        except S.Hung:
            outcome.append("hung")  # the lockstep wire ran dry: the server had nothing more to say
    w.close()
    srv.join(2)
    return list(w.log), outcome


class Crc(unittest.TestCase):
    """LINK_CRC with the table (BIOS half, msxpiext.bin) and without it (DOS half)."""

    def crc(self, image, data):
        import z80emu
        code, sym = image
        cpu = z80emu.Z80()
        cpu.mem[0x0100:0x0100 + len(code)] = code
        cpu.mem[0x8000:0x8000 + len(data)] = data
        cpu.sp = 0xF000
        cpu.run_call(sym["L2_CRC_INIT"])
        cpu.run_call(sym["LINK_CRC"], hl=0x8000, bc=len(data))
        cpu.run_call(sym["L2_CRC_GET"])
        return cpu.de

    def test_both_variants(self):
        rng = random.Random(7)
        samples = [b"123456789", b"", bytes(range(256)), bytes(rng.randrange(256) for _ in range(1000))]
        for extra in ([], ["-DLINK2_CRC_NOTABLE"]):
            image = z80_msx.assemble(extra)
            self.assertEqual(self.crc(image, b"123456789"), 0x29B1, extra)
            for data in samples:
                self.assertEqual(self.crc(image, data), binascii.crc_hqx(data, 0xFFFF), (extra, len(data)))


class RoomCeiling(unittest.TestCase):
    """Mode 2 has no caller size: a buffer below F380h must end by F380h (design 8.6)."""

    def run_recv(self, at, n):
        w = S.Wire(timeout=2.0)
        srv = S.Server(w, [lambda: B.link_send(pattern(n, 5))], True).start()
        m = z80_msx.Z80Msx(w, 8192, True)
        try:
            return bytes(m.recv(at=at))
        except (S.MsxAborted, S.Hung):    # the ABORT flood ends with the Pi giving up
            return "aborted"
        finally:
            w.close()
            srv.join(2)

    def test_fits(self):
        self.assertEqual(self.run_recv(0xF000, 0x300), pattern(0x300, 5))

    def test_past_the_system_area(self):
        self.assertEqual(self.run_recv(0xF300, 0x200), "aborted")

    def test_ends_exactly_at_the_ceiling(self):
        self.assertEqual(self.run_recv(0xF280, 0x100), pattern(0x100, 5))

    def test_ends_exactly_at_10000h_from_below_the_system_area(self):
        # HL wraps to 0: past F380h all the same, so it is refused (F100h keeps the
        # block clear of the emulator's stack below F000h)
        self.assertEqual(self.run_recv(0xF100, 0xF00), "aborted")


class ByteForByte(unittest.TestCase):
    def same(self, *a, **k):
        ref = trace(S.ModelMsx, *a, **k)
        z80 = trace(z80_msx.Z80Msx, *a, **k)
        if ref != z80:
            n = next((i for i, (x, y) in enumerate(zip(ref[0], z80[0])) if x != y), min(len(ref[0]), len(z80[0])))
            self.fail(f"{a} {k}: wire differs at transfer {n}: model {ref[0][max(0, n - 3):n + 4]} "
                      f"z80 {z80[0][max(0, n - 3):n + 4]}; outcomes {ref[1] == z80[1]}")

    def test_clean(self):
        for n in (1, 255, 256, 300, 512, 513, 1024, 8192, 8193, 20000):
            for has_wait in (True, False):
                for pi_burst in (True, False):
                    for direction in ("msx2pi", "pi2msx"):
                        self.same(direction, pattern(n, n), 8192, has_wait, pi_burst, follow=False)

    def test_small_blocks_and_page1(self):
        for direction in ("msx2pi", "pi2msx"):
            self.same(direction, pattern(5000, 3), 512, follow=False)
            self.same(direction, pattern(5000, 3), 600, follow=False)
            self.same(direction, pattern(2048, 4), 1024, may_burst=False, follow=False)
        self.same("msx2pi", b"", 8192, follow=False)

    def test_flips(self):
        r = random.Random(7)
        for direction in ("msx2pi", "pi2msx"):
            for n, size in ((300, 8192), (512, 8192), (700, 256)):
                data = pattern(n, n)
                for _ in range(40):
                    d = r.choice(("p2m", "m2p"))
                    i = r.randrange(n + 40)
                    self.same(direction, data, size, flips=[(d, i, 1 << r.randrange(8))])

    def test_slips(self):
        r = random.Random(8)
        for direction in ("msx2pi", "pi2msx"):
            for n, size in ((300, 8192), (600, 256)):
                for k in r.sample(range(n + 40), 30):
                    self.same(direction, pattern(n, n), size, slips=[k])

    def test_header_and_answer_damage(self):
        """Damage at the first bytes of every block and of the opening: the frames themselves."""
        for direction in ("msx2pi", "pi2msx"):
            for i in range(0, 24):
                for d in ("p2m", "m2p"):
                    self.same(direction, pattern(520, 1), 256, flips=[(d, i, 0x80)])


if __name__ == "__main__":
    unittest.main()
