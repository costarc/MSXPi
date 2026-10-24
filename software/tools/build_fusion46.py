#!/usr/bin/env python3
r"""Build fusion46.lib: the Fusion-C routines the MSXPi programs use, for SDCC 4.6.

    python tools/build_fusion46.py <output-dir> [--fusion-c <dir>]

The assembler routines are assembled from the Fusion-C source tree (source/lib/*.s) at build
time; they are not copied into this repository (Fusion-C is published under CC BY-SA 4.0 and
this repository is MIT). Their prototypes are in C-common/header/fusion.h, marked
__sdcccall(0). Print, PrintNumber, Width and ReadTPA are our own C (C-common/fusion/), compiled
here with SDCC's default convention, as the programs on the SDCC 4.6 path are.

The Fusion-C tree is --fusion-c, $FUSION_C, or ..\..\..\MSX\MSX-C\WorkingFolder\fusion-c
relative to software/, the place make.bat and make.sh use.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOFTWARE = Path(__file__).resolve().parent.parent

# Fusion-C source/lib/*.s, one per routine group declared in C-common/header/fusion.h
ASM = ['vram', 'fillvram', 'hideshowdisplay', 'inport', 'outport', 'inkey', 'inputchar', 'ctype',
       'joystickbios', 'locate', 'printchar', 'printhex', 'readmsxtype', 'readsp', 'screen', 'setdate',
       'strcompare', 'strcopy', 'fcb_open', 'fcb_read', 'fcb_find', 'vdpwrite', 'functionkeys',
       'setcolors', 'waitkey', 'cls', 'setpalette']


def run(cmd, cwd):
    done = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if done.returncode:
        sys.exit(f"{' '.join(map(str, cmd))}\n{done.stdout}{done.stderr}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument('outdir')
    ap.add_argument('--fusion-c', default=os.environ.get('FUSION_C') or
                    str(SOFTWARE / '../../../MSX/MSX-C/WorkingFolder/fusion-c'))
    a = ap.parse_args()
    src = Path(a.fusion_c).resolve() / 'source' / 'lib'
    if not src.is_dir():
        sys.exit(f'Fusion-C source not found: {src} (set FUSION_C or --fusion-c)')
    out = Path(a.outdir).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='fusion46-') as tmp:
        work = Path(tmp)
        rels = []
        for name in ASM:
            shutil.copy(src / f'{name}.s', work / f'{name}.s')
            run(['sdasz80', '-o', f'{name}.s'], work)
            rels.append(f'{name}.rel')
        run(['sdcc', '-mz80', '--opt-code-size', '-c', str(SOFTWARE / 'C-common/fusion/fusion46.c'),
             '-o', 'fusion46.rel'], work)
        rels.append('fusion46.rel')
        lib = out / 'fusion46.lib'
        if lib.exists():
            lib.unlink()
        run(['sdar', '-rc', str(lib)] + rels, work)
    print(f'{lib} ({len(rels)} modules)')


if __name__ == '__main__':
    main()
