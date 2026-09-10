#!/usr/bin/env python3
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
