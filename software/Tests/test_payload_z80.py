#!/usr/bin/env python3
"""Execute generated kernels/adapters with libz80ex (apt: libz80ex-dev).

Uses SDCC/SDAS to assemble the canonical engine and C ABI adapter. The ROM
variant is exercised separately by pcopy_emulator.py (including slot access).
"""
import ctypes as C
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
U8, U16, PTR = C.c_uint8, C.c_uint16, C.c_void_p
MR = C.CFUNCTYPE(U8, PTR, U16, C.c_int, PTR)
MW = C.CFUNCTYPE(None, PTR, U16, U8, PTR)
PR = C.CFUNCTYPE(U8, PTR, U16, PTR)
PW = C.CFUNCTYPE(None, PTR, U16, U8, PTR)
IR = C.CFUNCTYPE(U8, PTR, PTR)
AF, BC, DE, HL, AF2, BC2, DE2, HL2, IX, IY, PC, SP = range(12)
IFF1, IFF2 = 16, 17
LIB = C.CDLL('libz80ex.so.1')
LIB.z80ex_create.argtypes = [MR,PTR,MW,PTR,PR,PTR,PW,PTR,IR,PTR]
LIB.z80ex_create.restype = PTR
LIB.z80ex_get_reg.argtypes = [PTR, C.c_int]
LIB.z80ex_get_reg.restype = U16
LIB.z80ex_set_reg.argtypes = [PTR, C.c_int, U16]
LIB.z80ex_step.argtypes = [PTR]
LIB.z80ex_step.restype = C.c_int
LIB.z80ex_destroy.argtypes = [PTR]

class Machine:
    def __init__(self, image, tcp=False, delay=0, escape_after=None, stuck=False):
        self.mem=bytearray(image)
        self.tcp=tcp; self.delay=delay; self.escape_after=escape_after; self.stuck=stuck
        self.pending=False; self.polls=0; self.poll_left=0; self.reads=0
        self.requests=0; self.sent=[]; self.row=0xb4; self.errors=[]; self.keys=0
        def mr(cpu,addr,m1,user): return self.mem[addr]
        def mw(cpu,addr,value,user): self.mem[addr]=value
        def pr(cpu,port,user):
            port &= 255
            if port==0x57: return 0xfe if self.tcp else 0x0e
            if port==0xaa: return self.row
            if port==0xa9:
                self.keys+=1
                if self.row != 0xb7: self.errors.append('PPI upper bits changed')
                return 0xfb if self.escape_after is not None and self.polls>=self.escape_after else 0xff
            if port==0x56:
                self.polls+=1
                if self.stuck: return 0 if self.tcp else 1
                if self.poll_left:
                    self.poll_left-=1
                    return 0 if self.tcp else 1
                return 2 if self.tcp and self.pending else 0
            if port==0x5a:
                if not self.pending or self.poll_left: self.errors.append('unready or duplicate read')
                self.pending=False
                value=(self.reads*73+19)&255
                self.reads+=1
                return value
            self.errors.append(f'unexpected input {port:x}'); return 0
        def pw(cpu,port,value,user):
            port &= 255
            if port==0xaa: self.row=value
            elif port==0x56:
                if value or self.pending: self.errors.append('invalid request')
                self.requests+=1; self.pending=True; self.poll_left=self.delay
            elif port==0x5a:
                if self.poll_left and not self.tcp: self.errors.append('unready write')
                self.sent.append(value); self.poll_left=0 if self.tcp else self.delay
            else: self.errors.append(f'unexpected output {port:x}')
        self.callbacks=(MR(mr),MW(mw),PR(pr),PW(pw),IR(lambda *_:0xff))
        a,b,c,d,e=self.callbacks
        self.cpu=LIB.z80ex_create(a,None,b,None,c,None,d,None,e,None)
    def set(self,r,v): LIB.z80ex_set_reg(self.cpu,r,v)
    def get(self,r): return LIB.z80ex_get_reg(self.cpu,r)
    def run(self,entry,count,adapter=False,iff=1,network=False):
        for r in [AF2,BC2,DE2,HL2,IX,IY]: self.set(r,0x1234+r)
        self.set(IFF1,iff); self.set(IFF2,iff)
        self.set(DE,0x8000); self.set(BC,count); self.set(HL,0x8000 if network else 0)
        self.set(SP,0xf000); self.set(PC,entry)
        # Return to zero; ABI-0 arguments follow the return address.
        args=bytes([0,0,0,0x80,count&255,count>>8,0,0xe0])
        self.mem[0xf000:0xf008]=args
        ticks=0
        for _ in range(10000000):
            ticks+=LIB.z80ex_step(self.cpu)
            if self.get(PC)==0: break
        else: raise AssertionError('kernel failed to return')
        return ticks
    def close(self): LIB.z80ex_destroy(self.cpu)

class PayloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory(); work=Path(cls.tmp.name)
        # Export the actual static adapter for direct invocation by the CPU test.
        header=(ROOT/'C-common/lib/payload_generated.h').read_text().replace('static ', '')
        # Assemble the production UNAPI loop and its actual bounded poll helper.
        ops=(ROOT/'UNAPI/src/ethops.asm').read_text()
        trans=(ROOT/'UNAPI/src/ethtrans.asm').read_text()
        sections=[ops[ops.index('\nETH_TX_SUM:')+1:ops.index('; =============================================================================',ops.index('\nETH_TX_SUM:')+1)],
                  trans[trans.index('\nETH_WAIT_READY:')+1:trans.index('; --- ETH_WAIT_DATA:')]]
        converted=[]
        for section in sections:
            scope=section.split(':')[0]
            section=re.sub(r'(?<![A-Za-z_])\.(\w+)',lambda m:scope+'_'+m[1],section)
            section=section.replace('(ix+o_ETH_TMO)','0(ix)').replace('(ix+o_ETH_SUM)','1(ix)')
            section=section.replace('CTRL1','0x56').replace('DATA1','0x5a')
            for line in section.splitlines():
                line=line.split(';')[0].rstrip()
                if re.match(r'\s*(ld|cp)\s',line):
                    line=re.sub(r'(?<=[ ,])(0x[0-9a-f]+|[0-9]+)$',r'#\1',line)
                converted.append(line)
        network='\nvoid network_kernel(void) __naked { __asm\n'+'\n'.join(converted)+'\n__endasm; }\n'
        (work/'fixture.c').write_text('#include <stdint.h>\n'+header+network)
        subprocess.run(['sdcc','-mz80','--sdcccall','0','--no-std-crt0','--code-loc','0x100',
                        str(work/'fixture.c'),'-o',str(work/'fixture.ihx')],check=True)
        cls.image=bytearray(65536)
        for line in (work/'fixture.ihx').read_text().splitlines():
            rec=bytes.fromhex(line[1:]); n=rec[0]; addr=int.from_bytes(rec[1:3],'big')
            if rec[3]==0: cls.image[addr:addr+n]=rec[4:4+n]
        text=(work/'fixture.lst').read_text()
        cls.labels={m[2]:int(m[1],16)+0x100 for m in re.finditer(r'^\s*([0-9A-F]{6})\s+.*?\s([A-Za-z_][A-Za-z_0-9]*):',text,re.M)}
    @classmethod
    def tearDownClass(cls): cls.tmp.cleanup()
    def test_transfer_and_abi(self):
        for tcp in (False,True):
            for tx in (False,True):
                for adapter in (False,True):
                    for count in (0,1,255,256,257,512,8192):
                        for iff in (0,1):
                            with self.subTest(tcp=tcp,tx=tx,adapter=adapter,count=count,iff=iff):
                                m=Machine(self.image,tcp,delay=3)
                                try:
                                    expected=bytes((i*73+19)&255 for i in range(count))
                                    if tx: m.mem[0x8000:0x8000+count]=expected
                                    label=('_payload_' if adapter else 'PAYLOAD_')+('tx' if tx else 'rx') if adapter else ('PAYLOAD_TX' if tx else 'PAYLOAD_RX')
                                    m.run(self.labels[label],count,adapter,iff)
                                    self.assertEqual(m.errors,[])
                                    self.assertEqual(bytes(m.sent) if tx else bytes(m.mem[0x8000:0x8000+count]),expected)
                                    checksum=int.from_bytes(m.mem[0xe000:0xe002],'little') if adapter else m.get(HL)
                                    self.assertEqual(checksum,sum(expected)&65535)
                                    if adapter: self.assertEqual(m.get(HL)&255,0xe0)
                                    else:
                                        self.assertFalse(m.get(AF)&1)
                                        self.assertEqual(m.get(BC),0)
                                        self.assertEqual(m.get(DE),0x8000+count)
                                    self.assertEqual(m.get(SP),0xf002)
                                    for r in [AF2,BC2,DE2,HL2,IX,IY]: self.assertEqual(m.get(r),0x1234+r)
                                    self.assertEqual(m.get(IFF1),iff)
                                    self.assertEqual(m.row,0xb4)
                                    if not tx: self.assertEqual(m.requests,count)
                                finally: m.close()
    def test_network_transmit(self):
        for tcp in (False,True):
            for count in (0,1,255,256,257,1514):
                m=Machine(self.image,tcp,delay=3)
                try:
                    data=bytes((i*29+3)&255 for i in range(count))
                    m.mem[0x8000:0x8000+count]=data
                    m.mem[0x1234+IX]=1  # bounded readiness timeout
                    m.run(self.labels['ETH_TX_SUM'],count,network=True)
                    self.assertEqual(bytes(m.sent),data)
                    self.assertEqual(m.mem[0x1234+IX+1],sum(data)&255)
                    self.assertFalse(m.get(AF)&1)
                    self.assertEqual(m.keys,0)  # never scan the keyboard in UNAPI
                    self.assertEqual(m.errors,[])
                finally: m.close()
        m=Machine(self.image,stuck=True)
        try:
            m.mem[0x1234+IX]=1
            m.run(self.labels['ETH_TX_SUM'],1514,network=True)
            self.assertTrue(m.get(AF)&1)
            self.assertEqual(m.sent,[])
            self.assertEqual(m.keys,0)
        finally: m.close()

    def test_escape_busy_and_ready(self):
        for tcp in (False,True):
            for stuck in (False,True):
                for iff in (False,True):
                    m=Machine(self.image,tcp,escape_after=100,stuck=stuck)
                    try:
                        m.run(self.labels['PAYLOAD_RX'],8192,iff=iff)
                        self.assertTrue(m.get(AF)&1)
                        self.assertEqual(m.get(AF)>>8,0xe2)
                        self.assertLess(m.reads,8192)
                        self.assertEqual(m.get(BC),8192-m.reads)
                        self.assertEqual(m.get(DE),0x8000+m.reads)
                        self.assertEqual(m.get(IFF1),iff)
                        self.assertEqual(m.row,0xb4)
                    finally: m.close()
if __name__=='__main__': unittest.main()
