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

"""Compare a file inside an MSX FAT12 disk image with its host reference."""
import argparse
import hashlib
from pathlib import Path
from pcopy_emulator import extract


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('disk',type=Path)
    p.add_argument('dos_name',help='8.3 filename, for example PERF.ROM')
    p.add_argument('reference',type=Path)
    args=p.parse_args()
    actual=extract(args.disk,args.dos_name)
    expected=args.reference.read_bytes()
    print('Disk file:',len(actual),'bytes',hashlib.sha256(actual).hexdigest())
    print('Reference:',len(expected),'bytes',hashlib.sha256(expected).hexdigest())
    if actual!=expected: raise SystemExit('FAIL: contents differ')
    print('PASS: byte-identical')

if __name__=='__main__': main()
