"""Does pchess.com leave the stack enough room on the MSX-DOS memory tops seen?

MSX-DOS refuses a program that reaches the top of the TPA (the address in
0006h), and PChess refuses to start the TCP/IP link with less than
STACK_ROOM bytes (pchess_tcp.c) between its end and that top. The file holds
the whole image, data areas included, so the end is 0x100 + its size.

TOPS are measured with target/memtop.com (run MEMTOP after INL I: the
TCP/IP driver lowers the top). Add a machine when you measure one.

    python pchess_memory_test.py [path\\to\\pchess.com]
"""
import sys
from pathlib import Path

SOFTWARE = Path(__file__).resolve().parents[2]
STACK_ROOM = 768   # keep in step with pchess_tcp.c
TOPS = {
    'Panasonic FS-A1WSX, MSX-DOS 1.8, MSXPi': 0xD606,
    'Canon V-25, MSX-DOS 1, MSXPi, before INL': 0xCA06,
    'Canon V-25, MSX-DOS 1, MSXPi, INL I loaded (TCP/IP link)': 0xC806,
}


def main():
    com = Path(sys.argv[1]) if len(sys.argv) > 1 else SOFTWARE / 'target/pchess.com'
    end = 0x100 + com.stat().st_size
    failed = False
    print(f'{com.name}: {com.stat().st_size} bytes, image ends at 0x{end - 1:04X}')
    for name, top in TOPS.items():
        free = top - end
        ok = free >= STACK_ROOM
        failed |= not ok
        print(f'{"PASS" if ok else "FAIL"}: {name}: top 0x{top:04X}, {free} bytes free (need {STACK_ROOM})')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
