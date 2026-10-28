#!/usr/bin/env python3
"""Developer-only: assemble the Soccer stub (PLAYNET engine + src/glue.asm) and publish the profile.

    python rebuild.py --assembler sjasmplus                      release stub -> assets/stub.bin, profile.json
    python rebuild.py --assembler sjasmplus --test-gpf T.GPF --test-syms T.tcl
                                                                 scripted-input test build for the two-emulator
                                                                 rig: a GPF and the stub's symbols for Tcl; the
                                                                 committed files are not touched

The engine is copied from software/Client/src/playnet/engine/ into src/ so the package carries all its sources.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ENGINE = HERE.parents[2] / 'Client/src/playnet/engine/playnet_engine.asm'

ROM_SIZE = 32768
ROM_SHA256 = 'b9536809a1784afb2e49a43d80ba9c6c8c15cd31ecbd6c284e9bf62c6927dcd4'
ROM_CRC32 = 0x74BC8295
BASE = 0x4000
# C100h-C6FFh: TPA under every MSX-DOS set-up and never written by the game (measured over a full match)
STUB_LOAD, STUB_MAX = 0xC100, 1024
TRANSPORT, TRANSPORT_SIZE = 0xC500, 512           # 512: the TCP/IP UNAPI transport (its buffers and stack)
XIRQ = TRANSPORT + 6
EXPORTED = ('PN_TICK', 'PN_IRQ', 'PN_P1', 'PN_P2', 'pad1t', 'pad1c', 'pad2c', 'rng1', 'rng2', 'stubEnd')


def assemble(assembler, engine, scripted, out_dir):
    """Build the stub into out_dir: returns (bytes, symbols)."""
    src = HERE / 'src'
    shutil.copyfile(engine, src / 'playnet_engine.asm')
    out_dir = Path(out_dir)
    command = [assembler] + (['-DSCRIPTED'] if scripted else []) + [
        '--raw=' + str(out_dir / 'stub.bin'), '--sym=' + str(out_dir / 'stub.sym'), 'glue.asm']
    subprocess.run(command, cwd=src, check=True)
    symbols = {}
    for line in (out_dir / 'stub.sym').read_text().splitlines():
        match = re.match(r'([\w.]+):\s*EQU\s*0x([0-9A-Fa-f]+)', line)
        if match:
            symbols[match[1]] = int(match[2], 16)
    return (out_dir / 'stub.bin').read_bytes(), symbols


def make_profile(stub, symbols):
    patches = []

    def patch(cpu, expected, replacement, reason):
        patches.append({'offset': cpu - BASE, 'expected': bytes.fromhex(expected).hex(),
                        'replace': replacement.hex(), 'reason': reason})

    def word(value):
        return struct.pack('<H', symbols[value] if isinstance(value, str) else value)

    # The table of SOCCERNET.COM (soccernet.asm, label "patches"), without its two shortened RAM clears (the
    # stub no longer lives at F000h), plus the interrupt hook (PLAYNET).
    patch(0x4028, '220a41', bytes(3), 'Anti-copy write ld (410Ah),hl: a no-op on a cartridge, harmful in RAM')
    patch(0x4056, '221641', bytes(3), 'Anti-copy write ld (4116h),hl')
    patch(0x40C3, 'cbb6', bytes(2), 'res 6,(hl) on the VDP R1 template: black screen when run from RAM')
    patch(0x4565, 'b948', word('pad1c'), 'Player 1 read: cached value of this frame')
    patch(0x456A, 'f248', word('pad2c'), 'Player 2 read: cached value of this frame')
    patch(0x4897, 'b948', word('pad1t'), 'TICK site: lee_los_mandos, once per frame - exchange, then player 1')
    patch(0x48AD, 'f248', word('pad2c'), 'Player 2 read: cached value of this frame')
    patch(0x4032, 'cd254f', b'\xcd' + word('PN_IRQ'), 'Sound tick per interrupt -> PN_IRQ counts it; the stub ticks the driver')
    patch(0x404E, 'fc254f', b'\xfc' + word('PN_IRQ'), 'Catch-up sound tick (an interrupt pending after the frame) -> PN_IRQ')
    patch(0xB006, 'ed5f1f', b'\xcd' + word('rng1'), 'ld a,r : rra -> derived from the frame counter')
    patch(0xB028, 'ed5fe606', b'\xcd' + word('rng2') + b'\0', 'ld a,r : and 6 -> derived from the frame counter')
    patch(0x4096, '2e40', word(XIRQ), "H.KEYI hook (ld hl,402Eh at 4095h) -> the transport's XIRQ, which jumps to 402Eh")
    return {
        'format': 'msxpi-rom-patch', 'version': 2, 'id': 'soccer-msxpi-netplay-v1',
        'abi': ['msxpi-netplay-v1'],
        'source': {'size': ROM_SIZE, 'sha256': ROM_SHA256, 'crc32': ROM_CRC32, 'file': 'SOCCER.ROM'},
        'output': {'size': ROM_SIZE, 'fill': 0, 'mapper': 'plain', 'target': 'ram-image'},
        'requirements': ["The player's own SOCCER.ROM: Konami's Soccer (RC-732), 32 KB, the dump identified above",
                         'PLAYNET, over an MSXPi or over TCP/IP UNAPI (with a memory mapper)',
                         'Any MSX with 64 KB RAM on the MSXPi path'],
        'assets': {'stub': {'file': 'assets/stub.bin', 'sha256': hashlib.sha256(stub).hexdigest()}},
        'layout': [{'source': 'input', 'offset': 0, 'size': ROM_SIZE, 'destination': 0}],
        'patches': patches,
        'netplay': {
            'abi': 'msxpi-netplay-v1', 'game_id': 'soccer', 'title': "Konami's Soccer", 'roles': ['H', 'C'],
            'transport': 'lockstep', 'input_bytes': 1,
            'image': {'host': 'plain', 'base': BASE},
            'stub': {'asset': 'stub', 'load': STUB_LOAD, 'max': STUB_MAX},
            'transport_area': {'address': TRANSPORT, 'size': TRANSPORT_SIZE},
            # E000h-F37Fh (cleared at INIT, the stack from F380h down), and D500h-D5FFh, which the start-up
            # and the BIOS write on MSX-DOS's old stack (measured over a full match)
            'game_ram': [[0xD500, 0xD5FF], [0xE000, 0xF37F]],
            'irq_handler': 0x402E,
            'start': 'header-init',
            'min_playnet': 2, 'requires': []},
        'symbols': {name: symbols[name] for name in EXPORTED}}


def patcher():
    spec = importlib.util.spec_from_file_location('patch_rom', HERE.parents[1] / 'patch_rom.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def publish(assembler, engine):
    stub, symbols = assemble(assembler, engine, False, HERE / 'assets')
    (HERE / 'assets/stub.sym').unlink()
    profile = make_profile(stub, symbols)
    (HERE / 'profile.json').write_text(json.dumps(profile, indent=2) + '\n', encoding='utf-8')
    patcher().gpf_bytes(profile, {'stub': stub})         # it must compile
    print(f'Published profile; stub {len(stub)} of {STUB_MAX} bytes ({STUB_LOAD:04X}h-{symbols["stubEnd"] - 1:04X}h), '
          f'{len(profile["patches"])} patches')


def test_build(assembler, engine, gpf_path, syms_path):
    with tempfile.TemporaryDirectory() as out:
        stub, symbols = assemble(assembler, engine, True, out)
    profile = make_profile(stub, symbols)
    profile['id'] = 'soccer-msxpi-netplay-test'
    data = patcher().gpf_bytes(profile, {'stub': stub})
    Path(gpf_path).write_bytes(data)
    if syms_path:
        Path(syms_path).write_text(''.join('set ::sym(%s) 0x%04X\n' % (k, v) for k, v in sorted(symbols.items())))
        Path(syms_path).with_suffix('.bin').write_bytes(stub)      # the stub, for the rig's code check
    print(f'Test GPF {gpf_path}: {len(data)} bytes, stub {len(stub)} bytes, '
          f'profile hash {struct.unpack_from("<I", data, 8)[0]:08x}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--assembler', required=True, help='sjasmplus executable')
    parser.add_argument('--engine', type=Path, default=ENGINE, help='PLAYNET engine source')
    parser.add_argument('--test-gpf', type=Path, help='write a scripted-input test GPF here instead of publishing')
    parser.add_argument('--test-syms', type=Path, help='with --test-gpf: the stub symbols as Tcl (set ::sym(..)), '
                                                       'and the stub itself beside it (.bin)')
    args = parser.parse_args()
    if args.test_gpf:
        test_build(args.assembler, args.engine, args.test_gpf, args.test_syms)
    else:
        publish(args.assembler, args.engine)
