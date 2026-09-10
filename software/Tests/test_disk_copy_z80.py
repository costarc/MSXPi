#!/usr/bin/env python3
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
addresses=(0x0200,0x3d00,0x3e00,0x3eff,0x3f00,0x3fff,0x4000,0x7dff,0x7e00,0x7fff,0x8000)
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
            m.mem[0xf36e]=0xc3 if mode=='DOS' else 0xc9
            m.mem[0xf342]=0x83  # RAMAD1
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
                    elif pc==0x000c:
                        v=read(m.get(HL));m.set(AF,v<<8);m.set(BC,0xdead);m.set(DE,0xbeef);ret()
                    elif pc==0x0014:
                        write(m.get(HL),m.get(DE)&255);m.set(AF,0xbeef);m.set(BC,0xdead);m.set(DE,0xfeed);ret()
                    else: LIB.z80ex_step(m.cpu)
                else: raise AssertionError('timeout')
                assert bytes(read(dst+i) for i in range(512))==data,(mode,receive,hex(address))
                assert bytes(m.mem[0x4000:0x8000])==original,'ROM overwritten'
                assert m.get(HL)==src+512 and m.get(DE)==dst+512 and m.get(BC)==0
                assert m.get(SP)==0xef02 and not m.get(AF)&1
                assert m.get(IFF1)==1
                expected=mode=='DOS' and 0x3e00<=address<0x8000
                assert calls==int(expected),(mode,address,calls)
                tests+=1
            finally: m.close()
print('PASS:',tests,'DOS/BASIC sector copies, read/write boundaries and ROM preservation')

# ROM space was recovered by replacing the unrolled parser with a loop.
# Exercise every 16-bit value and invalid characters at each digit position.
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
for receive, fail, sectors in product((False, True), (False, True), (1, 2)):
    m=Machine(image)
    private=0xc800+label('UNAPI_WRKEND')
    caller=0xc000
    payload=bytes((i*17+(i//512)*23+31)&255 for i in range(512*sectors))
    m.mem[0xf34d:0xf34f]=(0xd000).to_bytes(2,'little')
    m.mem[0xd000:0xd200]=bytes([0xa5])*512
    m.mem[caller:caller+512*sectors]=bytes([0x77])*(512*sectors) if receive else payload
    m.set(DE,caller);m.set(BC,(sectors<<8)|0xf9);m.set(AF,0);m.set(SP,0xef00)
    m.set(PC,label('DSKIO_READ_LOOP' if receive else 'DSKIO_WRITE_LOOP'))
    getwrk=label('GETWRK'); handshake=label('PerformHandshake')
    transfer=label('RECVDATA_ONEBLOCK' if receive else 'SENDDATA')
    calls=0
    def ret():
        sp=m.get(SP);m.set(PC,int.from_bytes(m.mem[sp:sp+2],'little'));m.set(SP,sp+2)
    try:
        for _ in range(10000):
            pc=m.get(PC)
            if pc==0: break
            if pc==getwrk:
                m.set(HL,0xc800);m.set(IX,0xc800);m.set(BC,0xdead);m.set(AF,0x1234);ret()
            elif pc==handshake:
                m.set(AF,0);ret()
            elif pc==transfer:
                assert m.get(DE)==private and m.get(BC)==512
                block=payload[calls*512:(calls+1)*512]
                if receive: m.mem[private:private+512]=block
                else: assert bytes(m.mem[private:private+512])==block
                m.set(DE,private+512);m.set(BC,0);m.set(HL,0xbeef)
                m.set(AF,int(fail));calls+=1;ret()
            else: LIB.z80ex_step(m.cpu)
        else: raise AssertionError('disk loop timeout')
        assert calls==(1 if fail else sectors) and bool(m.get(AF)&1)==fail
        assert bytes(m.mem[0xd000:0xd200])==bytes([0xa5])*512, 'kernel buffer clobbered'
        expected=bytes([0x77])*(512*sectors) if receive and fail else payload
        assert bytes(m.mem[caller:caller+512*sectors])==expected
    finally: m.close()
print('PASS: disk loops use private buffer, preserve kernel scratch, reject failed reads')
