#!/usr/bin/env python3
"""Cost test for netcore on the Z80: builds it with SDCC as src/playnet/build.py does (-mz80 --opt-code-size),
runs netcore_cost_bench.c in sz80 (SDCC's simulator) with a stub host, and fails when one sending nc_xchg
takes more than MAX_INSTRUCTIONS instructions. PLAYNET-TCPIP-PERFORMANCE.md 5.1 and 8.1: with the old
32-bit clock it was 2167, with ticks about 250.

    python netcore_cost.py [--sdcc path]
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
NETCORE = HERE.parent / 'src/playnet/netcore'
MAX_INSTRUCTIONS = 400
CALLS = 40


def find_tool(name, given):
    found = given or shutil.which(name) or shutil.which(name, path='C:/Apps/SDCC/bin')
    if not found:
        raise SystemExit(f'{name} not found: put SDCC on PATH or pass --sdcc')
    return found


def run(*args, cwd):
    done = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if done.returncode:
        raise SystemExit(' '.join(args) + '\n' + done.stdout + done.stderr)
    return done.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sdcc')
    args = parser.parse_args()
    sdcc = find_tool('sdcc', args.sdcc)
    sz80 = find_tool('sz80', str(Path(sdcc).with_name('sz80')) if args.sdcc else None)
    with tempfile.TemporaryDirectory() as tmp:
        for src in (NETCORE / 'netcore.c', HERE / 'netcore_cost_bench.c'):
            run(sdcc, '-mz80', '--opt-code-size', '-c', '-I', str(NETCORE), str(src), cwd=tmp)
        run(sdcc, '-mz80', 'netcore_cost_bench.rel', 'netcore.rel', '-o', 'bench.ihx', cwd=tmp)
        marker = re.search(r'([0-9A-F]{8})\s+_marker\b', (Path(tmp) / 'bench.map').read_text())
        out = subprocess.run([sz80, '-t', 'Z80', 'bench.ihx'], cwd=tmp, capture_output=True, text=True, timeout=60,
                             input='break 0x%X\nrun\nstate\nrun\nstate\nquit\n' % int(marker[1], 16)).stdout
    counts = [int(n) for n in re.findall(r'Inst=\s*(\d+)', out)]
    if len(counts) != 2:
        raise SystemExit('unexpected simulator output:\n' + out)
    per_call = (counts[1] - counts[0]) // CALLS
    print(f'nc_xchg (sending 22 bytes): {per_call} instructions per call, limit {MAX_INSTRUCTIONS}')
    return 0 if per_call <= MAX_INSTRUCTIONS else 1


if __name__ == '__main__':
    sys.exit(main())
