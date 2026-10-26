"""A small Z80 interpreter for the LINK2 tests (documents/LINK2-TEST-PLAN.md, T3).

Documented instructions only (no IXH/IXL halves), with T-states, port I/O hooks and
address traps.  It exists so the assembled link2.asm runs against the real server
code over the lockstep wire of link2_sim.py, and so a routine's T-states per byte
can be counted (the sz80 simulator of SDCC cannot hook the MSXPi ports).
"""

PARITY = [bin(i).count("1") % 2 == 0 for i in range(256)]
S_, Z_, Y_, H_, X_, P_, N_, C_ = 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01


class Halt(Exception):
    pass


class Z80:
    def __init__(self):
        self.mem = bytearray(65536)
        self.r = [0] * 8  # B C D E H L (unused) A  -> index 0..7, 6 = F here
        self.af2 = self.bc2 = self.de2 = self.hl2 = 0
        self.ix = self.iy = 0
        self.sp = 0xF000
        self.pc = 0
        self.iff1 = self.iff2 = False
        self.i = 0
        self.t = 0  # T-states
        self.m1_wait = 1  # the MSX adds one wait state to every opcode fetch (M1); 0 for a bare Z80
        self.n = 0  # instructions
        self.io_in = lambda port: 0xFF
        self.io_out = lambda port, v: None
        self.traps = {}  # address -> callable(cpu); must perform the RET itself
        self.max_instr = 50_000_000

    # --- register access ---------------------------------------------------
    @property
    def a(self): return self.r[7]
    @a.setter
    def a(self, v): self.r[7] = v & 0xFF
    @property
    def f(self): return self.r[6]
    @f.setter
    def f(self, v): self.r[6] = v & 0xFF
    def get16(self, i): return (self.r[2 * i] << 8) | self.r[2 * i + 1]
    def set16(self, i, v):
        self.r[2 * i] = (v >> 8) & 0xFF
        self.r[2 * i + 1] = v & 0xFF
    @property
    def bc(self): return self.get16(0)
    @bc.setter
    def bc(self, v): self.set16(0, v)
    @property
    def de(self): return self.get16(1)
    @de.setter
    def de(self, v): self.set16(1, v)
    @property
    def hl(self): return self.get16(2)
    @hl.setter
    def hl(self, v): self.set16(2, v)
    @property
    def af(self): return (self.r[7] << 8) | self.r[6]
    @af.setter
    def af(self, v):
        self.r[7] = (v >> 8) & 0xFF
        self.r[6] = v & 0xFF

    # --- memory ------------------------------------------------------------
    def rb(self, a): return self.mem[a & 0xFFFF]
    def wb(self, a, v): self.mem[a & 0xFFFF] = v & 0xFF
    def rw(self, a): return self.mem[a & 0xFFFF] | (self.mem[(a + 1) & 0xFFFF] << 8)
    def ww(self, a, v):
        self.mem[a & 0xFFFF] = v & 0xFF
        self.mem[(a + 1) & 0xFFFF] = (v >> 8) & 0xFF
    def fetch(self):
        v = self.mem[self.pc]
        self.pc = (self.pc + 1) & 0xFFFF
        return v
    def fetch16(self):
        lo = self.fetch()
        return lo | (self.fetch() << 8)
    def push(self, v):
        self.sp = (self.sp - 2) & 0xFFFF
        self.ww(self.sp, v)
    def pop(self):
        v = self.rw(self.sp)
        self.sp = (self.sp + 2) & 0xFFFF
        return v

    # --- flags and ALU -------------------------------------------------------
    def szp(self, v, extra=0):
        return (v & (S_ | Y_ | X_)) | (Z_ if v == 0 else 0) | (P_ if PARITY[v] else 0) | extra

    def alu(self, op, v):
        a = self.a
        if op in (0, 1):  # ADD, ADC
            c = (self.f & C_) if op == 1 else 0
            res = a + v + c
            h = ((a & 0xF) + (v & 0xF) + c) > 0xF
            ov = (~(a ^ v) & (a ^ res) & 0x80) != 0
            self.f = (res & (S_ | Y_ | X_)) | (Z_ if (res & 0xFF) == 0 else 0) | (H_ if h else 0) \
                | (P_ if ov else 0) | (C_ if res > 0xFF else 0)
            self.a = res
        elif op in (2, 3, 7):  # SUB, SBC, CP
            c = (self.f & C_) if op == 3 else 0
            res = a - v - c
            h = ((a & 0xF) - (v & 0xF) - c) < 0
            ov = ((a ^ v) & (a ^ res) & 0x80) != 0
            yx = v if op == 7 else res
            self.f = (res & S_) | (yx & (Y_ | X_)) | (Z_ if (res & 0xFF) == 0 else 0) | (H_ if h else 0) \
                | (P_ if ov else 0) | N_ | (C_ if res < 0 else 0)
            if op != 7:
                self.a = res
        elif op == 4:
            self.a = a & v
            self.f = self.szp(self.a, H_)
        elif op == 5:
            self.a = a ^ v
            self.f = self.szp(self.a)
        elif op == 6:
            self.a = a | v
            self.f = self.szp(self.a)

    def inc8(self, v):
        res = (v + 1) & 0xFF
        self.f = (self.f & C_) | (res & (S_ | Y_ | X_)) | (Z_ if res == 0 else 0) \
            | (H_ if (v & 0xF) == 0xF else 0) | (P_ if v == 0x7F else 0)
        return res

    def dec8(self, v):
        res = (v - 1) & 0xFF
        self.f = (self.f & C_) | (res & (S_ | Y_ | X_)) | (Z_ if res == 0 else 0) \
            | (H_ if (v & 0xF) == 0 else 0) | (P_ if v == 0x80 else 0) | N_
        return res

    def add16(self, a, b):
        res = a + b
        self.f = (self.f & (S_ | Z_ | P_)) | ((res >> 8) & (Y_ | X_)) \
            | (H_ if ((a & 0xFFF) + (b & 0xFFF)) > 0xFFF else 0) | (C_ if res > 0xFFFF else 0)
        return res & 0xFFFF

    def adc16(self, a, b, sub=False):
        c = self.f & C_
        if sub:
            res = a - b - c
            h = ((a & 0xFFF) - (b & 0xFFF) - c) < 0
            ov = ((a ^ b) & (a ^ res) & 0x8000) != 0
        else:
            res = a + b + c
            h = ((a & 0xFFF) + (b & 0xFFF) + c) > 0xFFF
            ov = (~(a ^ b) & (a ^ res) & 0x8000) != 0
        r16 = res & 0xFFFF
        self.f = ((r16 >> 8) & (S_ | Y_ | X_)) | (Z_ if r16 == 0 else 0) | (H_ if h else 0) \
            | (P_ if ov else 0) | (N_ if sub else 0) | (C_ if (res < 0 or res > 0xFFFF) else 0)
        return r16

    def cond(self, cc):
        f = self.f
        return [not f & Z_, bool(f & Z_), not f & C_, bool(f & C_),
                not f & P_, bool(f & P_), not f & S_, bool(f & S_)][cc]

    # --- operand helpers -----------------------------------------------------
    def reg_get(self, i, idx=None, d=0):
        if i == 6:
            return self.rb(self.hl if idx is None else (idx + d))
        return self.r[i]

    def reg_set(self, i, v, idx=None, d=0):
        if i == 6:
            self.wb(self.hl if idx is None else (idx + d), v)
        else:
            self.r[i] = v & 0xFF

    def rp_get(self, p, idx=None):
        return [self.bc, self.de, self.hl if idx is None else idx, self.sp][p]

    def rp_set(self, p, v):
        v &= 0xFFFF
        if p == 0: self.bc = v
        elif p == 1: self.de = v
        elif p == 2: self.hl = v
        else: self.sp = v

    # --- run ---------------------------------------------------------------------
    def run_call(self, addr, ret_addr=0xFFF0, **regs):
        """CALL addr and run until it returns to ret_addr."""
        for k, v in regs.items():
            setattr(self, k, v)
        self.push(ret_addr)
        self.pc = addr
        t0, n0 = self.t, self.n
        while self.pc != ret_addr:
            self.step()
            if self.n - n0 > self.max_instr:
                raise Halt("instruction limit")
        return self.t - t0, self.n - n0

    def step(self):
        if self.pc in self.traps:
            self.traps[self.pc](self)
            return
        self.n += 1
        op = self.fetch()
        self.t += self.m1_wait
        if op == 0xCB:
            self.t += self.m1_wait      # a prefix is a second M1
            self.cb(None, 0)
        elif op == 0xED:
            self.t += self.m1_wait
            self.ed()
        elif op in (0xDD, 0xFD):
            self.t += self.m1_wait
            self.indexed(op)
        else:
            self.main(op, None)

    def main(self, op, idx):
        x, y, z = op >> 6, (op >> 3) & 7, op & 7
        p, q = y >> 1, y & 1
        if x == 0:
            if z == 0:
                if y == 0: self.t += 4
                elif y == 1:
                    self.af, self.af2 = self.af2, self.af
                    self.t += 4
                elif y == 2:
                    d = self.fetch(); d = d - 256 if d > 127 else d
                    self.r[0] = (self.r[0] - 1) & 0xFF
                    if self.r[0]:
                        self.pc = (self.pc + d) & 0xFFFF
                        self.t += 13
                    else:
                        self.t += 8
                elif y == 3:
                    d = self.fetch(); d = d - 256 if d > 127 else d
                    self.pc = (self.pc + d) & 0xFFFF
                    self.t += 12
                else:
                    d = self.fetch(); d = d - 256 if d > 127 else d
                    if self.cond(y - 4):
                        self.pc = (self.pc + d) & 0xFFFF
                        self.t += 12
                    else:
                        self.t += 7
            elif z == 1:
                if q == 0:
                    v = self.fetch16()
                    if p == 2 and idx is not None:
                        self.set_idx(idx, v)
                    else:
                        self.rp_set(p, v)
                    self.t += 10
                else:
                    hl = self.get_idx(idx) if idx is not None else self.hl
                    res = self.add16(hl, self.rp_get(p, self.get_idx(idx) if idx is not None else None))
                    if idx is not None: self.set_idx(idx, res)
                    else: self.hl = res
                    self.t += 11
            elif z == 2:
                if p == 0:
                    if q == 0: self.wb(self.bc, self.a)
                    else: self.a = self.rb(self.bc)
                    self.t += 7
                elif p == 1:
                    if q == 0: self.wb(self.de, self.a)
                    else: self.a = self.rb(self.de)
                    self.t += 7
                elif p == 2:
                    nn = self.fetch16()
                    if q == 0:
                        self.ww(nn, self.get_idx(idx) if idx is not None else self.hl)
                    else:
                        v = self.rw(nn)
                        if idx is not None: self.set_idx(idx, v)
                        else: self.hl = v
                    self.t += 16
                else:
                    nn = self.fetch16()
                    if q == 0: self.wb(nn, self.a)
                    else: self.a = self.rb(nn)
                    self.t += 13
            elif z == 3:
                if idx is not None and p == 2:
                    v = self.get_idx(idx)
                    self.set_idx(idx, v + 1 if q == 0 else v - 1)
                else:
                    self.rp_set(p, self.rp_get(p) + (1 if q == 0 else -1))
                self.t += 6 if idx is None else 10
            elif z in (4, 5):
                d = 0
                if y == 6 and idx is not None:
                    d = self.fetch(); d = d - 256 if d > 127 else d
                v = self.reg_get(y, self.get_idx(idx) if idx is not None else None, d)
                v = self.inc8(v) if z == 4 else self.dec8(v)
                self.reg_set(y, v, self.get_idx(idx) if idx is not None else None, d)
                self.t += (4 if y != 6 else (11 if idx is None else 23))
            elif z == 6:
                d = 0
                if y == 6 and idx is not None:
                    d = self.fetch(); d = d - 256 if d > 127 else d
                n = self.fetch()
                self.reg_set(y, n, self.get_idx(idx) if idx is not None else None, d)
                self.t += 7 if y != 6 else (10 if idx is None else 19)
            else:  # z == 7
                a = self.a
                if y == 0:
                    self.a = ((a << 1) | (a >> 7)) & 0xFF
                    self.f = (self.f & (S_ | Z_ | P_)) | (self.a & (Y_ | X_)) | (a >> 7)
                elif y == 1:
                    self.a = ((a >> 1) | (a << 7)) & 0xFF
                    self.f = (self.f & (S_ | Z_ | P_)) | (self.a & (Y_ | X_)) | (a & 1)
                elif y == 2:
                    self.a = ((a << 1) | (self.f & C_)) & 0xFF
                    self.f = (self.f & (S_ | Z_ | P_)) | (self.a & (Y_ | X_)) | (a >> 7)
                elif y == 3:
                    self.a = ((a >> 1) | ((self.f & C_) << 7)) & 0xFF
                    self.f = (self.f & (S_ | Z_ | P_)) | (self.a & (Y_ | X_)) | (a & 1)
                elif y == 4:
                    raise Halt("DAA not supported")
                elif y == 5:
                    self.a = a ^ 0xFF
                    self.f = (self.f & (S_ | Z_ | P_ | C_)) | (self.a & (Y_ | X_)) | H_ | N_
                elif y == 6:
                    self.f = (self.f & (S_ | Z_ | P_)) | (a & (Y_ | X_)) | C_
                else:
                    c = self.f & C_
                    self.f = (self.f & (S_ | Z_ | P_)) | (a & (Y_ | X_)) | (H_ if c else 0) | (0 if c else C_)
                self.t += 4
        elif x == 1:
            if op == 0x76:
                raise Halt("HALT")
            d = 0
            if idx is not None and (y == 6 or z == 6):
                d = self.fetch(); d = d - 256 if d > 127 else d
            base = self.get_idx(idx) if idx is not None else None
            if y == 6:
                self.reg_set(6, self.r[z], base, d)  # source never H/L when (IX+d) is the target
            elif z == 6:
                self.r[y] = self.reg_get(6, base, d)
            else:
                self.r[y] = self.r[z]
            self.t += 4 if (y != 6 and z != 6) else (7 if idx is None else 19)
        elif x == 2:
            d = 0
            if z == 6 and idx is not None:
                d = self.fetch(); d = d - 256 if d > 127 else d
            v = self.reg_get(z, self.get_idx(idx) if idx is not None else None, d)
            self.alu(y, v)
            self.t += 4 if z != 6 else (7 if idx is None else 19)
        else:
            if z == 0:
                if self.cond(y):
                    self.pc = self.pop()
                    self.t += 11
                else:
                    self.t += 5
            elif z == 1:
                if q == 0:
                    v = self.pop()
                    if p == 3: self.af = v
                    elif p == 2 and idx is not None: self.set_idx(idx, v)
                    else: self.rp_set(p, v)
                    self.t += 10
                else:
                    if p == 0:
                        self.pc = self.pop(); self.t += 10
                    elif p == 1:
                        self.t += 4
                        self.exx()
                    elif p == 2:
                        self.pc = self.get_idx(idx) if idx is not None else self.hl
                        self.t += 4
                    else:
                        self.sp = self.get_idx(idx) if idx is not None else self.hl
                        self.t += 6
            elif z == 2:
                nn = self.fetch16()
                if self.cond(y): self.pc = nn
                self.t += 10
            elif z == 3:
                if y == 0:
                    self.pc = self.fetch16(); self.t += 10
                elif y == 1:
                    raise Halt("CB in main")
                elif y == 2:
                    n = self.fetch()
                    self.io_out((self.a << 8) | n, self.a)
                    self.t += 11
                elif y == 3:
                    n = self.fetch()
                    self.a = self.io_in((self.a << 8) | n)
                    self.t += 11
                elif y == 4:
                    hl = self.get_idx(idx) if idx is not None else self.hl
                    v = self.rw(self.sp)
                    self.ww(self.sp, hl)
                    if idx is not None: self.set_idx(idx, v)
                    else: self.hl = v
                    self.t += 19
                elif y == 5:
                    self.de, self.hl = self.hl, self.de
                    self.t += 4
                elif y == 6:
                    self.iff1 = self.iff2 = False; self.t += 4
                else:
                    self.iff1 = self.iff2 = True; self.t += 4
            elif z == 4:
                nn = self.fetch16()
                if self.cond(y):
                    self.push(self.pc)
                    self.pc = nn
                    self.t += 17
                else:
                    self.t += 10
            elif z == 5:
                if q == 0:
                    v = self.af if p == 3 else (self.get_idx(idx) if (p == 2 and idx is not None) else self.rp_get(p))
                    self.push(v)
                    self.t += 11
                elif p == 0:
                    nn = self.fetch16()
                    self.push(self.pc)
                    self.pc = nn
                    self.t += 17
                else:
                    raise Halt("bad opcode %02X" % op)
            elif z == 6:
                self.alu(y, self.fetch())
                self.t += 7
            else:
                self.push(self.pc)
                self.pc = y * 8
                self.t += 11

    def exx(self):
        bc, de, hl = self.bc, self.de, self.hl
        self.bc, self.de, self.hl = self.bc2, self.de2, self.hl2
        self.bc2, self.de2, self.hl2 = bc, de, hl

    def get_idx(self, idx): return self.ix if idx == 0xDD else self.iy
    def set_idx(self, idx, v):
        if idx == 0xDD: self.ix = v & 0xFFFF
        else: self.iy = v & 0xFFFF

    def indexed(self, prefix):
        op = self.fetch()
        if op == 0xCB:
            d = self.fetch(); d = d - 256 if d > 127 else d
            sub = self.fetch()
            self.cb(prefix, d, sub)
        else:
            self.main(op, prefix)
            self.t += 4

    def cb(self, prefix, d, sub=None):
        if sub is None:
            sub = self.fetch()
        x, y, z = sub >> 6, (sub >> 3) & 7, sub & 7
        base = self.get_idx(prefix) if prefix else None
        v = self.reg_get(z if prefix is None else 6, base, d)
        if x == 0:
            c = self.f & C_
            if y == 0: res = ((v << 1) | (v >> 7)) & 0xFF; nc = v >> 7
            elif y == 1: res = ((v >> 1) | (v << 7)) & 0xFF; nc = v & 1
            elif y == 2: res = ((v << 1) | c) & 0xFF; nc = v >> 7
            elif y == 3: res = ((v >> 1) | (c << 7)) & 0xFF; nc = v & 1
            elif y == 4: res = (v << 1) & 0xFF; nc = v >> 7
            elif y == 5: res = (v >> 1) | (v & 0x80); nc = v & 1
            elif y == 6: res = ((v << 1) | 1) & 0xFF; nc = v >> 7
            else: res = v >> 1; nc = v & 1
            self.f = self.szp(res, nc)
            self.reg_set(z if prefix is None else 6, res, base, d)
        elif x == 1:
            bit = (v >> y) & 1
            self.f = (self.f & C_) | H_ | (Z_ | P_ if not bit else 0) | (S_ if (y == 7 and bit) else 0)
        else:
            res = v & ~(1 << y) if x == 2 else v | (1 << y)
            self.reg_set(z if prefix is None else 6, res, base, d)
        mem = (z == 6) if prefix is None else True
        self.t += (8 if not mem else (12 if x == 1 else 15)) if prefix is None else (20 if x == 1 else 23)

    def ed(self):
        op = self.fetch()
        x, y, z = op >> 6, (op >> 3) & 7, op & 7
        p, q = y >> 1, y & 1
        if x == 1:
            if z == 0:
                v = self.io_in(self.bc)
                self.f = self.szp(v, self.f & C_)
                if y != 6: self.r[y] = v
                self.t += 12
            elif z == 1:
                self.io_out(self.bc, self.r[y] if y != 6 else 0)
                self.t += 12
            elif z == 2:
                self.hl = self.adc16(self.hl, self.rp_get(p), sub=(q == 0))
                self.t += 15
            elif z == 3:
                nn = self.fetch16()
                if q == 0: self.ww(nn, self.rp_get(p))
                else: self.rp_set(p, self.rw(nn))
                self.t += 20
            elif z == 4:
                v = self.a
                self.a = 0
                self.alu(2, v)
                self.t += 8
            elif z == 5:
                self.pc = self.pop()
                self.iff1 = self.iff2
                self.t += 14
            elif z == 6:
                self.t += 8
            else:
                if y == 0: self.i = self.a
                elif y == 2:
                    self.a = self.i
                    self.f = (self.f & C_) | (self.a & (S_ | Y_ | X_)) | (Z_ if self.a == 0 else 0) \
                        | (P_ if self.iff2 else 0)
                elif y == 3: pass
                else: raise Halt("ED %02X" % op)
                self.t += 9
        elif x == 2 and z <= 3 and y >= 4:
            kind = y - 4  # 0 inc, 1 dec, 2 inc repeat, 3 dec repeat
            step = 1 if kind in (0, 2) else -1
            rep = kind >= 2
            if z == 0:  # LDI/LDD/LDIR/LDDR
                self.wb(self.de, self.rb(self.hl))
                self.hl += step; self.de += step; self.bc = self.bc - 1
                self.f = (self.f & (S_ | Z_ | C_)) | (P_ if self.bc else 0)
                if rep and self.bc:
                    self.pc = (self.pc - 2) & 0xFFFF; self.t += 21
                else:
                    self.t += 16
            elif z == 2:  # INI/IND/INIR/INDR
                self.wb(self.hl, self.io_in(self.bc))
                self.r[0] = (self.r[0] - 1) & 0xFF
                self.hl += step
                self.f = (self.f & C_) | N_ | (Z_ if self.r[0] == 0 else 0)
                if rep and self.r[0]:
                    self.pc = (self.pc - 2) & 0xFFFF; self.t += 21
                else:
                    self.t += 16
            elif z == 3:  # OUTI/OUTD/OTIR/OTDR
                v = self.rb(self.hl)
                self.r[0] = (self.r[0] - 1) & 0xFF
                self.io_out(self.bc, v)
                self.hl += step
                self.f = (self.f & C_) | N_ | (Z_ if self.r[0] == 0 else 0)
                if rep and self.r[0]:
                    self.pc = (self.pc - 2) & 0xFFFF; self.t += 21
                else:
                    self.t += 16
            else:
                raise Halt("CPI not supported")
        else:
            self.t += 8
