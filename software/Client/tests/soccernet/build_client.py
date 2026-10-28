#!/usr/bin/env python3
"""Build one MSX-DOS C client (software/Client/src/NAME.c) into a folder, for the test rigs.

    python build_client.py mchat OUTDIR [--sdcc sdcc] [--fusion C:/Users/roniv/Dev/MSX/MSX-C/WorkingFolder/fusion-c]

The same compiler and options as software/make.bat (SDCC 4.6, its own calling convention, code at 0106h,
fusion-c's crt0_msxdos, msxpi-bios.lib, fusion46.lib from tools/build_fusion46.py), but it works from any
checkout and writes only OUTDIR/NAME.COM: make.bat also copies the program into target/ and into the
emulator's floppy folder.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[2]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('name')
    ap.add_argument('outdir')
    ap.add_argument('--sdcc', default=shutil.which('sdcc') or 'sdcc')
    ap.add_argument('--fusion', default='C:/Users/roniv/Dev/MSX/MSX-C/WorkingFolder/fusion-c')
    args = ap.parse_args()
    sdcc = args.sdcc
    tools = Path(sdcc).parent
    fusion = Path(args.fusion)
    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        def run(*cmd):
            done = subprocess.run(cmd, cwd=tmp, capture_output=True, text=True)
            if done.returncode:
                raise SystemExit(' '.join(map(str, cmd)) + '\n' + done.stdout + done.stderr)
            return done
        run(sys.executable, str(SOFTWARE / 'tools/build_fusion46.py'), tmp, '--fusion-c', str(fusion))
        run(sdcc, '-mz80', '-c', str(SOFTWARE / 'C-common/lib/msxpi-bios.c'))
        run(str(tools / 'sdar'), '-rc', 'msxpi-bios.lib', 'msxpi-bios.rel')
        run(sdcc, '--code-loc', '0x106', '--data-loc', '0x0', '--disable-warning', '196', '-mz80', '--no-std-crt0',
            '--opt-code-size', 'fusion46.lib', 'msxpi-bios.lib', '-L', tmp,
            str(fusion / 'include/crt0_msxdos.rel'),
            str(SOFTWARE / 'Client/src' / (args.name + '.c')))
        # gaps (the uninitialised globals) are FFh, as hex2bin leaves them in make.bat's .COM: crt0_msxdos zeroes
        # nothing, so a program that needs a zero there must write it, and the rig must not hide that
        image = bytearray(b'\xff' * 0x10000)
        top = 0
        for line in (Path(tmp) / (args.name + '.ihx')).read_text().splitlines():
            n, addr, kind = int(line[1:3], 16), int(line[3:7], 16), int(line[7:9], 16)
            if kind == 0 and n:
                image[addr:addr + n] = bytes.fromhex(line[9:9 + 2 * n])
                top = max(top, addr + n)
        com = bytes(image[0x100:top])
        (out / (args.name.upper() + '.COM')).write_bytes(com)
        shutil.copyfile(Path(tmp) / (args.name + '.map'), out / (args.name + '.map'))
    print(f'{args.name.upper()}.COM {len(com)} bytes, image ends at {top - 1:04X}h')


if __name__ == '__main__':
    main()
