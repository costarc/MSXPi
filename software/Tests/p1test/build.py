#!/usr/bin/env python3
"""Assemble p1test.asm with zmac and pad it to 40 KB with the test pattern.

    python3 build.py [path/to/zmac(.exe)]   ->  P1TEST.COM next to this file
"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORG, PADSTART, PADEND = 0x0100, 0x0400, 0xA100
zmac = sys.argv[1] if len(sys.argv) > 1 else str(Path.home()/'Dev/zmac/zmac.exe')

with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([zmac, '--oo', 'hex', '--od', tmp, str(HERE/'p1test.asm')], check=True)
    image = bytearray(PADEND - ORG)
    for line in (Path(tmp)/'p1test.hex').read_text().split():
        n, addr, kind = int(line[1:3], 16), int(line[3:7], 16), int(line[7:9], 16)
        if kind == 0:
            image[addr-ORG:addr-ORG+n] = bytes.fromhex(line[9:9+2*n])
for a in range(PADSTART, PADEND):
    image[a-ORG] = (a & 0xFF) ^ (a >> 8) ^ 0xA5
(HERE/'P1TEST.COM').write_bytes(image)
print(f'P1TEST.COM {len(image)} bytes (pattern {PADSTART:04X}-{PADEND-1:04X})')
