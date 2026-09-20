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

"""Assemble p1test.asm with zmac and pad it to 40 KB with the test pattern,
and assemble p1w.asm (MSX-DOS 1 page-1 write/read test) as is.

    python3 build.py [path/to/zmac(.exe)]   ->  P1TEST.COM, P1W.COM next to this file
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

# P1W.COM: code only, up to the last assembled byte.
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([zmac, '--oo', 'hex', '--od', tmp, str(HERE/'p1w.asm')], check=True)
    image, end = bytearray(0x3E00 - ORG), ORG
    for line in (Path(tmp)/'p1w.hex').read_text().split():
        n, addr, kind = int(line[1:3], 16), int(line[3:7], 16), int(line[7:9], 16)
        if kind == 0:
            image[addr-ORG:addr-ORG+n] = bytes.fromhex(line[9:9+2*n])
            end = max(end, addr + n)
(HERE/'P1W.COM').write_bytes(image[:end-ORG])
print(f'P1W.COM {end-ORG} bytes')
