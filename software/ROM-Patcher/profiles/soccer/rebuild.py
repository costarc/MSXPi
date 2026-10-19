#!/usr/bin/env python3
"""Developer-only: assemble the Soccer netplay stub and publish the declarative profile.

The stub is still today's SOCCERNET stub (MSXPi transport inside it, handshake at frame 0), copied
from software/Client/src/soccernet/stub.tmpl.asm into src/. It is 729 bytes, more than the 576 the
profile reserves for the PLAYNET layout (stub F000h-F23Fh, transport F240h-F2FFh), so `patch_rom.py
--gpf` refuses this package until the stub is rebuilt from the PLAYNET engine (implementation step 4).
The patches are exactly SOCCERNET's; tests/test_gpf.py proves the image byte for byte.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess

HERE = Path(__file__).resolve().parent
ENGINE = HERE.parents[2] / 'Client/src/soccernet/stub.tmpl.asm'

ROM_SIZE = 32768
ROM_SHA256 = 'b9536809a1784afb2e49a43d80ba9c6c8c15cd31ecbd6c284e9bf62c6927dcd4'
ROM_CRC32 = 0x74BC8295
BASE = 0x4000


def rebuild(assembler, engine):
    src = HERE / 'src'
    src.mkdir(exist_ok=True)
    (HERE / 'assets').mkdir(exist_ok=True)
    shutil.copyfile(engine, src / 'stub.tmpl.asm')
    # The scripted-input tables only exist in test builds (-DSCRIPTED); the release stub has none.
    text = (src / 'stub.tmpl.asm').read_text()
    (src / 'stub.asm').write_text(text.replace('@SCR0@', '').replace('@SCR1@', ''))
    subprocess.run([assembler, '-DNATIVE', '--raw=../assets/stub.bin', '--sym=stub.sym', 'stub.asm'],
                   cwd=src, check=True)
    symbols = {}
    for line in (src / 'stub.sym').read_text().splitlines():
        match = re.match(r'(\w+):\s*EQU\s*0x([0-9A-Fa-f]+)', line)
        if match:
            symbols[match[1]] = int(match[2], 16)
    stub = (HERE / 'assets/stub.bin').read_bytes()
    patches = []

    def patch(cpu, expected, replacement, reason):
        patches.append({'offset': cpu - BASE, 'expected': bytes.fromhex(expected).hex(),
                        'replace': replacement.hex(), 'reason': reason})

    def word(symbol):
        return struct.pack('<H', symbols[symbol])

    # The same table, in the same order, as SOCCERNET.COM (soccernet.asm, label "patches").
    patch(0x4028, '220a41', bytes(3), 'Anti-copy write ld (410Ah),hl: a no-op on a cartridge, harmful in RAM')
    patch(0x4056, '221641', bytes(3), 'Anti-copy write ld (4116h),hl')
    patch(0x40C3, 'cbb6', bytes(2), 'res 6,(hl) on the VDP R1 template: black screen when run from RAM')
    patch(0x4565, 'b948', word('pad1c'), 'Player 1 read: cached value of this frame')
    patch(0x456A, 'f248', word('pad2c'), 'Player 2 read: cached value of this frame')
    patch(0x4897, 'b948', word('pad1t'), 'TICK site: lee_los_mandos, once per frame - exchange, then player 1')
    patch(0x48AD, 'f248', word('pad2c'), 'Player 2 read: cached value of this frame')
    patch(0x4032, 'cd254f', bytes(3), 'Sound driver ticked per interrupt: the stub ticks it once per frame')
    patch(0x404E, 'fc254f', bytes(3), 'Catch-up sound tick when an interrupt is pending after the frame')
    patch(0x40A5, '7f13', struct.pack('<H', 0x0FFF), 'INIT RAM clear stops at EFFFh, so the stub at F000h survives')
    patch(0x45A9, '9f11', struct.pack('<H', 0x0F1F), 'Match RAM clear (from E0E0h) stops at EFFFh')
    patch(0xB006, 'ed5f1f', b'\xcd' + word('rng1'), 'ld a,r : rra -> derived from the frame counter')
    patch(0xB028, 'ed5fe606', b'\xcd' + word('rng2') + b'\0', 'ld a,r : and 6 -> derived from the frame counter')

    exported = ('pad1t', 'pad1c', 'pad2c', 'rng1', 'rng2', 'ROLE', 'stubEnd')
    profile = {
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
            'stub': {'asset': 'stub', 'load': 0xF000, 'max': 576},
            'transport_area': {'address': 0xF240, 'size': 192},
            # E000h-EFFFh after the two shortened clears; the stack from F37Fh down to F30Ch (measured)
            'game_ram': [[0xE000, 0xEFFF], [0xF30C, 0xF37F]],
            'irq_handler': 0x402E,
            'start': 'header-init',
            'min_playnet': 1},
        'symbols': {name: symbols[name] for name in exported}}
    (HERE / 'profile.json').write_text(json.dumps(profile, indent=2) + '\n', encoding='utf-8')
    print(f'Published profile; stub {len(stub)} bytes (F000h-{symbols["stubEnd"] - 1:04X}h), '
          f'{len(patches)} patches')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--assembler', required=True, help='sjasmplus executable')
    parser.add_argument('--engine', type=Path, default=ENGINE, help='stub template (default: the SOCCERNET one)')
    args = parser.parse_args()
    rebuild(args.assembler, args.engine)
