#!/usr/bin/env python3
# MSXPi Interface
# Version 1.6
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

"""Execute the ROM sector-copy helper across slot boundaries.

Usage: python3 test_disk_copy_z80.py ROM LISTING
XFER/RDSLT/WRSLT are modeled as BIOS contracts; full openMSX copy tests exercise
those kernel implementations. The ROM itself supplies all copy/dispatch code.
"""
import sys
from pathlib import Path
import re
from test_payload_z80 import Machine, LIB, AF, BC, DE, HL, PC, SP, IX, IFF1, IFF2

rom=Path(sys.argv[1]).read_bytes()
listing=Path(sys.argv[2]).read_text()
def label(name):
    m=re.search(r'^'+name+r'[ \t]+=?[ \t]*([0-9a-fA-F]{1,4})\s',listing,re.M|re.I)
    if not m: raise AssertionError('label missing: '+name)
    return int(m[1],16)
image=bytearray(65536);image[0x4000:0x8000]=rom
entry=label('DSKIO_COPY_SECTOR')
# The helper is only called for a caller buffer that can touch page 1
# (3E00-7FFF, including sectors crossing into or out of it). It must copy
# through XFER, or fail with carry when XFER is disabled (Disk BASIC).
addresses=(0x3e00,0x3eff,0x3f00,0x3fff,0x4000,0x7dff,0x7e00,0x7fff)
tests=0
for mode in ('DOS','BASIC'):
    for receive in (False,True):
        for address in addresses:
            m=Machine(image);ram=bytearray(0x4000);data=bytes((i*73+19)&255 for i in range(512))
            src,dst=(0xc000,address) if receive else (address,0xc000)
            def read(a): return ram[a-0x4000] if 0x4000<=a<0x8000 else m.mem[a]
            def write(a,v):
                if 0x4000<=a<0x8000: ram[a-0x4000]=v
                else: m.mem[a]=v
            for i,v in enumerate(data): write(src+i,v)
            before=bytes(read(dst+i) for i in range(512))
            m.mem[0xf36e]=0xc3 if mode=='DOS' else 0xc9
            original=bytes(m.mem[0x4000:0x8000])
            m.set(HL,src);m.set(DE,dst);m.set(BC,0xaaaa);m.set(SP,0xef00);m.set(PC,entry)
            m.set(IFF1,1);m.set(IFF2,1)
            calls=0
            def ret():
                sp=m.get(SP);m.set(PC,int.from_bytes(m.mem[sp:sp+2],'little'));m.set(SP,sp+2)
            try:
                for _ in range(100000):
                    pc=m.get(PC)
                    if pc==0: break
                    if pc==0xf36e:
                        assert mode=='DOS';calls+=1
                        a,b,n=m.get(HL),m.get(DE),m.get(BC)
                        assert n==512
                        payload=bytes(read(a+i) for i in range(n))
                        for i,v in enumerate(payload): write(b+i,v)
                        m.set(HL,a+n);m.set(DE,b+n);m.set(BC,0);ret()
                    else: LIB.z80ex_step(m.cpu)
                else: raise AssertionError('timeout')
                assert bytes(m.mem[0x4000:0x8000])==original,'ROM overwritten'
                assert m.get(SP)==0xef02 and m.get(IFF1)==1
                if mode=='DOS':
                    assert calls==1 and not m.get(AF)&1,(mode,hex(address))
                    assert bytes(read(dst+i) for i in range(512))==data,(mode,receive,hex(address))
                    assert m.get(HL)==src+512 and m.get(DE)==dst+512 and m.get(BC)==0
                else:
                    assert calls==0 and m.get(AF)&1,'XFER disabled must fail the sector'
                    assert bytes(read(dst+i) for i in range(512))==before,'copied without XFER'
                tests+=1
            finally: m.close()
print('PASS:',tests,'page-1 sector copies: XFER in DOS, clean failure in BASIC, ROM preserved')

hex_entry=label('STRTOHEX')
for value in range(65536):
    m=Machine(image)
    try:
        digits=f'{value:04x}' if value&1 else f'{value:04X}'
        m.mem[0xc000:0xc006]=(digits+' !').encode()
        m.set(DE,0xc000);m.set(HL,0xabcd);m.set(SP,0xef00);m.set(PC,hex_entry)
        for _ in range(160):
            if m.get(PC)==0: break
            LIB.z80ex_step(m.cpu)
        assert m.get(PC)==0 and m.get(BC)==value and m.get(DE)==0xc005
        assert m.get(HL)==0xabcd and not m.get(AF)&1
    finally: m.close()
for pos in range(4):
    for bad in ('/', ':', '@', 'G', '`', 'g'):
        m=Machine(image)
        try:
            text='1234';text=text[:pos]+bad+text[pos+1:]
            m.mem[0xc000:0xc004]=text.encode()
            m.set(DE,0xc000);m.set(HL,0xabcd);m.set(SP,0xef00);m.set(PC,hex_entry)
            for _ in range(160):
                if m.get(PC)==0: break
                LIB.z80ex_step(m.cpu)
            assert m.get(PC)==0 and m.get(AF)&1 and m.get(DE)==0xc000+pos
            assert m.get(HL)==0xabcd
        finally: m.close()
print('PASS: ROM hexadecimal parser, all 65536 values and invalid digits')

# Execute the real disk loops with protocol calls modeled. The shared kernel
# buffer must survive ordinary reads/writes, and failed reads must not commit.
from itertools import product
# Disk loops: a caller buffer outside page 1 is transferred directly (no
# staging); one in page 1 is staged through the private buffer and XFER.
# Neither may touch the kernel's shared sector buffer (SECBUF).
for caller, receive, fail, sectors in product((0xc000, 0x4000), (False, True), (False, True), (1, 2)):
    m=Machine(image)
    ram=bytearray(0x4000)
    def read(a): return ram[a-0x4000] if 0x4000<=a<0x8000 else m.mem[a]
    def write(a,v):
        if 0x4000<=a<0x8000: ram[a-0x4000]=v
        else: m.mem[a]=v
    staged=caller<0x8000
    private=0xc800+label('UNAPI_WRKEND')
    payload=bytes((i*17+(i//512)*23+31)&255 for i in range(512*sectors))
    m.mem[0xf36e]=0xc3
    m.mem[0xf34d:0xf34f]=(0xd000).to_bytes(2,'little')
    m.mem[0xd000:0xd200]=bytes([0xa5])*512
    initial=bytes([0x77])*(512*sectors) if receive else payload
    for i,v in enumerate(initial): write(caller+i,v)
    m.set(DE,caller);m.set(BC,(sectors<<8)|0xf9);m.set(AF,0);m.set(SP,0xef00)
    m.set(PC,label('DSKIO_READ_LOOP' if receive else 'DSKIO_WRITE_LOOP'))
    getwrk=label('GETWRK'); handshake=label('PerformHandshake')
    transfer=label('RECVDATA_ONEBLOCK' if receive else 'SENDDATA')
    calls=xfers=0
    def ret():
        sp=m.get(SP);m.set(PC,int.from_bytes(m.mem[sp:sp+2],'little'));m.set(SP,sp+2)
    try:
        for _ in range(20000):
            pc=m.get(PC)
            if pc==0: break
            if pc==getwrk:
                m.set(HL,0xc800);m.set(IX,0xc800);m.set(BC,0xdead);m.set(AF,0x1234);ret()
            elif pc==handshake:
                m.set(AF,0);ret()
            elif pc==0xf36e:
                xfers+=1
                a,b,n=m.get(HL),m.get(DE),m.get(BC)
                assert n==512
                block=bytes(read(a+i) for i in range(n))
                for i,v in enumerate(block): write(b+i,v)
                m.set(HL,a+n);m.set(DE,b+n);m.set(BC,0);ret()
            elif pc==transfer:
                where=private if staged else caller+calls*512
                assert m.get(DE)==where and m.get(BC)==512,(hex(m.get(DE)),hex(where))
                block=payload[calls*512:(calls+1)*512]
                if receive:
                    for i,v in enumerate(block): write(where+i,v)
                else: assert bytes(read(where+i) for i in range(512))==block
                # Transport leaves DE/HL arbitrary: the loops must not rely on them.
                m.set(DE,0xbeef);m.set(BC,0);m.set(HL,0xbeef)
                m.set(AF,int(fail));calls+=1;ret()
            else: LIB.z80ex_step(m.cpu)
        else: raise AssertionError('disk loop timeout')
        assert calls==(1 if fail else sectors) and bool(m.get(AF)&1)==fail
        done=0 if fail else sectors
        # a staged write copies before sending; a staged read copies only after a good receive
        assert xfers==((done if receive else calls) if staged else 0),(hex(caller),receive,fail,xfers)
        assert bytes(m.mem[0xd000:0xd200])==bytes([0xa5])*512, 'kernel buffer clobbered'
        expected=initial if receive and fail else payload
        if receive and fail and not staged:
            # A direct read lands in the caller's buffer before it is rejected (as in R1);
            # DSKIO reports the error and DOS discards it. Later sectors stay untouched.
            expected=payload[:512]+initial[512:]
        assert bytes(read(caller+i) for i in range(512*sectors))==expected
    finally: m.close()
print('PASS: disk loops direct outside page 1, staged via XFER in page 1, reject failed reads')
