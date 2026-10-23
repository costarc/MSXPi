#!/usr/bin/env python3
"""Developer-only: assemble the Salamander stub (PLAYNET engine + 8 KB mapper host + src/glue.asm) and write
the profile.

    python rebuild.py --assembler sjasmplus                  stub -> assets/stub.bin, profile.json
    python rebuild.py --assembler sjasmplus --rom SALAMAND.ROM
                                                             also check every patch's expected bytes against
                                                             the dump, and that no bank-register write is left
    python rebuild.py --assembler sjasmplus --test-gpf T.GPF --test-syms T.tcl
                                                             scripted-input test build for the two-emulator
                                                             rig: a GPF and the stub's symbols for Tcl; the
                                                             committed files are not touched

The package uses image host "mapper-ram" (documents/SALAMANDER-DESIGN.md, section 5): PLAYNET release 3.
The engine and the mapper host are copied from software/Client/src/playnet/engine/ into src/.
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
import zlib

HERE = Path(__file__).resolve().parent
ENGINE_DIR = HERE.parents[2] / 'Client/src/playnet/engine'
ENGINE_FILES = ('playnet_engine.asm', 'mapper_k8.asm')

ROM_SIZE = 131072
ROM_SHA256 = 'edbbba820ac67d6a55b9dc5da9309e45979936d5620c07d09793efaf077e86b9'
ROM_CRC32 = 0xC36F559D
BANK = 0x2000
TRANSPORT, TRANSPORT_SIZE = 0xD000, 512        # first: on the TCP/IP path it is also in MSX-DOS's page 3 (TPA top D706h, Nextor)
STUB_LOAD, STUB_MAX = 0xD200, 1792
XIRQ = TRANSPORT + 6
EXPORTED = ('PN_TICK', 'PN_IRQ', 'PN_P1', 'PN_P2', 'MK_BLOCK', 'MK_SEG2', 'MK_W0', 'MK_W1', 'MK_W2', 'MK_W3',
            'sndTick', 'tickSite', 'p1', 'dual', 'fkeys', 'f5key', 'keyY', 'keyN', 'probeOff', 'clrRam', 'rnd', 'stubEnd')

# The 8 KB window each bank runs in (from the bank-select routines at 416Eh-41FFh and the traces)
WINDOW_OF_BANK = {0: 0x4000, 1: 0x6000, 4: 0x6000, 7: 0x6000, 13: 0x6000,
                  2: 0x8000, 5: 0x8000, 8: 0x8000, 10: 0x8000, 14: 0x8000,
                  3: 0xA000, 6: 0xA000, 9: 0xA000, 11: 0xA000, 12: 0xA000, 15: 0xA000}
BANK_REGISTERS = {0x5000: 'MK_W0', 0x7000: 'MK_W1', 0x9000: 'MK_W2', 0xB000: 'MK_W3'}

# Every ld (nn),a to a bank register, as (bank, CPU address, register). The sites mapper_detect.py finds,
# all of them confirmed by the traces, less the two SCC enables of the sound driver (SCC_NOPS).
BANK_SWITCHES = [
    (0, 0x4087, 0x7000), (0, 0x408B, 0x9000), (0, 0x408F, 0xB000), (0, 0x409D, 0x7000), (0, 0x40A3, 0x9000),
    (0, 0x40A9, 0xB000), (0, 0x40F5, 0x5000), (0, 0x40FB, 0x7000), (0, 0x4101, 0x9000), (0, 0x4108, 0xB000),
    (0, 0x4185, 0x7000), (0, 0x418B, 0x9000), (0, 0x4191, 0xB000), (0, 0x419C, 0x9000), (0, 0x41A4, 0xB000),
    (0, 0x41B3, 0x9000), (0, 0x41DB, 0x9000), (0, 0x41E2, 0xB000), (0, 0x41F1, 0x7000), (0, 0x41F8, 0x9000),
    (0, 0x4D77, 0x7000), (0, 0x4D7B, 0x9000), (0, 0x4D7F, 0xB000), (0, 0x4D8A, 0x7000), (0, 0x4D90, 0x9000),
    (0, 0x4D96, 0xB000), (0, 0x50E5, 0x7000), (0, 0x50E9, 0x9000), (0, 0x50ED, 0xB000), (0, 0x50F6, 0x7000),
    (0, 0x50FC, 0x9000), (0, 0x5102, 0xB000), (0, 0x5BBD, 0x7000), (0, 0x5BC1, 0x9000), (0, 0x5BC5, 0xB000),
    (0, 0x5BD0, 0x5000), (1, 0x6E54, 0x9000),
    (4, 0x65CD, 0x9000), (4, 0x6622, 0x9000), (4, 0x734A, 0x9000), (4, 0x7351, 0x9000), (4, 0x73AB, 0x9000),
    (4, 0x73C4, 0x9000),
]

# Konami SCC sound: in RAM there is no SCC, and its registers (9800h-98FFh, enabled by 3Fh in 9000h) would be
# written into the bank copies. The sound driver's SCC writes go; its PSG part stays.
SCC_NOPS = [(4, 0x65C4, '320090'), (4, 0x65C8, '328f98'), (4, 0x6606, '320090'), (4, 0x660D, '328f98'),
            (4, 0x6611, '328a98'), (4, 0x6614, '328b98'), (4, 0x6617, '328c98'), (4, 0x661A, '328d98'),
            (4, 0x661D, '328e98')]
SCC_RETS = [(4, 0x7346, '7e', 'one SCC register write (16 callers at 729Eh-7342h)'),
            (4, 0x73A9, '3e', 'SCC waveform upload (from 7355h)')]

# ld a,r and the instruction after it -> call to the glue's deterministic version
LD_A_R = [(0, 0x4E58, 'ed5f47', 'rLdB'), (1, 0x65AB, 'ed5f0f', 'rRrca'), (1, 0x67DA, 'ed5fe607', 'rAnd07'),
          (1, 0x718B, 'ed5fae', 'rXorHL'), (1, 0x7274, 'ed5fe678', 'rAnd78'), (1, 0x73D5, 'ed5fe63f', 'rAnd3F'),
          (1, 0x7544, 'ed5f47', 'rLdB'), (10, 0x99F1, 'ed5f1f', 'rRra'), (10, 0x9CCA, 'ed5f87', 'rAdd'),
          (10, 0x9CD3, 'ed5f87', 'rAdd'), (12, 0xAE7A, 'ed5fe61f', 'rAnd1F'), (12, 0xB03A, 'ed5fe61f', 'rAnd1F')]

# Pairs the loader builds. Page 1: all four the game uses. Page 2: the first six are pinned and are the homes
# of the banks with page 1's four; the rest follow in the order of use measured over ten minutes of play,
# then the six possible pairs never seen. The loader builds as many as the machine has segments for.
PAGE1_PAIRS = [(0, 1), (0, 4), (0, 7), (0, 13)]
PAGE2_PAIRS = [(2, 3), (5, 6), (8, 9), (10, 11), (14, 15), (2, 12),
               (2, 15), (14, 3), (2, 11), (2, 6), (5, 3), (2, 9), (10, 15), (10, 3), (5, 15), (14, 6), (5, 12),
               (5, 11), (5, 9), (8, 6), (10, 6), (10, 9), (8, 3), (8, 11),
               (8, 12), (8, 15), (10, 12), (14, 9), (14, 11), (14, 12)]
PINNED = (4, 6)
MIN_SEGMENTS, RECOMMENDED_SEGMENTS = 22, 30


def offset(bank, cpu):
    assert WINDOW_OF_BANK[bank] <= cpu < WINDOW_OF_BANK[bank] + BANK, (bank, hex(cpu))
    return bank * BANK + (cpu - WINDOW_OF_BANK[bank])


def assemble(assembler, engine_dir, scripted, out_dir):
    """Build the stub into out_dir: returns (bytes, symbols)."""
    src = HERE / 'src'
    for name in ENGINE_FILES:
        shutil.copyfile(Path(engine_dir) / name, src / name)
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


def make_patches(symbols):
    patches = []

    def word(value):
        return struct.pack('<H', symbols[value] if isinstance(value, str) else value)

    def patch(bank, cpu, expected, replacement, reason):
        patches.append({'offset': offset(bank, cpu), 'expected': bytes.fromhex(expected).hex(),
                        'replace': replacement.hex(), 'reason': f'{cpu:04X}h (bank {bank}): {reason}'})

    # The frame and the inputs (all in bank 0, fixed at 4000h-5FFFh)
    patch(0, 0x40E3, '6940', word(XIRQ), "H.KEYI hook (ld hl,4069h at 40E2h) -> the transport's XIRQ, which jumps to 4069h")
    patch(0, 0x406D, '2af7f02322f7', b'\xcd' + word('PN_IRQ') + b'\xc3\xac\x40',
          'Interrupt: count it (PN_IRQ) and go to the frame at 40ACh; its counters, timer and sound move to sndTick')
    patch(0, 0x40B5, 'cda751', b'\xcd' + word('tickSite'), 'TICK site: the input reader, once per frame -> PN_TICK, then the reader')
    patch(0, 0x514F, 'fdcb214620', b'\xcd' + word('dual') + b'\x18\x64',
          "DUALPLAY: a player block's port -> player 1's or player 2's input by the block (IY), then the edge logic at 51B8h")
    patch(0, 0x51B2, 'cdbf51', b'\xcd' + word('p1'), 'One player (1PLAYER, EXCHANGE): player 1')
    patch(0, 0x521F, '3e06cd4101', b'\xcd' + word('fkeys') + b'\x18\x1e',
          'Function keys (pause, continue) from either player, then on at 5242h')
    patch(0, 0x55F9, '3e07cd', b'\xc3' + word('f5key'), 'F5 (CONTINUE F5) from either player')
    patch(0, 0x57CC, '3e05cd', b'\xc3' + word('keyY'), 'Y of the Y/N prompt, from either player')
    patch(0, 0x57D4, '3e04cd', b'\xc3' + word('keyN'), 'N of the Y/N prompt, from either player')
    patch(0, 0x57DC, 'cdff51', b'\xcd' + word('p1'), 'Menus (PLAY SELECT): player 1, the inviter')
    patch(0, 0x410B, '2100e0', b'\xcd' + word('clrRam'),
          'INIT: clear C000h-CFFFh, F000h-F0DFh and F0F7h too, so both machines start from the same RAM')
    patch(3, 0xB59D, '010004', b'\xc3' + word('probeOff'),
          'Cartridge probe (Nemesis 2 in another slot): none, on both machines')
    for bank, cpu, expected, routine in LD_A_R:
        patch(bank, cpu, expected, b'\xcd' + word(routine) + bytes(len(expected) // 2 - 3),
              f'ld a,r -> {routine}, deterministic')
    for bank, cpu, register in BANK_SWITCHES:
        name = BANK_REGISTERS[register]
        patch(bank, cpu, '32' + word(register).hex(), b'\xcd' + word(name), f'ld ({register:04X}h),a -> {name}')
    for bank, cpu, expected in SCC_NOPS:
        patch(bank, cpu, expected, bytes(3), 'SCC (no SCC in RAM): removed')
    for bank, cpu, expected, what in SCC_RETS:
        patch(bank, cpu, expected, b'\xc9', f'SCC: ret, {what}')
    patches.sort(key=lambda p: p['offset'])
    return patches


def make_profile(stub, symbols):
    return {
        'format': 'msxpi-rom-patch', 'version': 2, 'id': 'salamander-msxpi-netplay-v1',
        'abi': ['msxpi-netplay-v1'],
        'source': {'size': ROM_SIZE, 'sha256': ROM_SHA256, 'crc32': ROM_CRC32, 'file': 'SALAMAND.ROM'},
        'output': {'size': ROM_SIZE, 'fill': 0, 'mapper': 'konami-scc', 'target': 'ram-image'},
        'requirements': ["The player's own SALAMAND.ROM: Konami's Salamander (RC-758), 128 KB, the dump identified above",
                         'PLAYNET release 3, over an MSXPi or over TCP/IP UNAPI',
                         f'A memory mapper with at least {MIN_SEGMENTS} free 16 KB segments for the game '
                         f'(512 KB recommended: {RECOMMENDED_SEGMENTS} segments play without pauses)'],
        'assets': {'stub': {'file': 'assets/stub.bin', 'sha256': hashlib.sha256(stub).hexdigest()}},
        'layout': [{'source': 'input', 'offset': 0, 'size': ROM_SIZE, 'destination': 0}],
        'patches': make_patches(symbols),
        'netplay': {
            'abi': 'msxpi-netplay-v1', 'game_id': 'salamand', 'title': 'Salamander (co-op)', 'roles': ['P1', 'P2'],
            'transport': 'lockstep', 'input_bytes': 2,
            'image': {'host': 'mapper-ram', 'mapper': 'konami-scc', 'bank_size': BANK, 'banks': ROM_SIZE // BANK,
                      'block': symbols['MK_BLOCK'], 'start_banks': [0, 1, 2, 3],
                      'page1_pairs': [list(p) for p in PAGE1_PAIRS], 'page2_pairs': [list(p) for p in PAGE2_PAIRS],
                      'pinned': list(PINNED), 'min_segments': MIN_SEGMENTS,
                      'recommended_segments': RECOMMENDED_SEGMENTS},
            'stub': {'asset': 'stub', 'load': STUB_LOAD, 'max': STUB_MAX},
            'transport_area': {'address': TRANSPORT, 'size': TRANSPORT_SIZE},
            # C000h-CFFFh and E000h-F0F8h (the stack from F0F0h down): measured over ten minutes of play
            'game_ram': [[0xC000, 0xCFFF], [0xDA00, 0xDDFF], [0xE000, 0xF0F8]],   # DA00h-DDFFh: the bank engine's pair map
            'irq_handler': 0x4069,
            'start': 'header-init',
            'min_playnet': 3},
        'symbols': {name: symbols[name] for name in EXPORTED}}


def check_rom(rom, profile):
    """Every expected byte is in the dump; no bank-register write survives; the pairs cover every bank."""
    assert len(rom) == ROM_SIZE and hashlib.sha256(rom).hexdigest() == ROM_SHA256, 'not the dump this package is for'
    out = bytearray(rom)
    end = -1
    for p in profile['patches']:
        expected, replace = bytes.fromhex(p['expected']), bytes.fromhex(p['replace'])
        o = p['offset']
        assert o >= end, f'patches overlap at {o:05X}h'
        assert rom[o:o + len(expected)] == expected, f'{p["reason"]}: found {rom[o:o + len(expected)].hex()}'
        out[o:o + len(replace)] = replace
        end = o + len(expected)
    left = []
    for o in range(len(out) - 2):
        if out[o] == 0x32 and (out[o + 1] | out[o + 2] << 8) in BANK_REGISTERS:
            left.append(o)
    homes = {b for pair in PAGE1_PAIRS + PAGE2_PAIRS[:PINNED[1]] for b in pair}
    assert homes == set(range(ROM_SIZE // BANK)), f'banks without a home: {set(range(16)) - homes}'
    return out, left


def patcher():
    spec = importlib.util.spec_from_file_location('patch_rom', HERE.parents[1] / 'patch_rom.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_build(assembler, engine_dir, gpf_path, syms_path):
    with tempfile.TemporaryDirectory() as out:
        stub, symbols = assemble(assembler, engine_dir, True, out)
    profile = make_profile(stub, symbols)
    profile['id'] = 'salamander-msxpi-netplay-test'
    data = patcher().gpf_bytes(profile, {'stub': stub})
    Path(gpf_path).write_bytes(data)
    if syms_path:
        Path(syms_path).write_text(''.join('set ::sym(%s) 0x%04X\n' % (k, v) for k, v in sorted(symbols.items())))
        Path(syms_path).with_suffix('.bin').write_bytes(stub)      # the stub, for the rig's code check
    print(f'Test GPF {gpf_path}: {len(data)} bytes, stub {len(stub)} bytes, '
          f'profile hash {struct.unpack_from("<I", data, 8)[0]:08x}')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--assembler', required=True, help='sjasmplus executable')
    parser.add_argument('--engine-dir', type=Path, default=ENGINE_DIR, help='PLAYNET engine sources')
    parser.add_argument('--rom', type=Path, help="the player's SALAMAND.ROM, to check the patches against")
    parser.add_argument('--test-gpf', type=Path, help='write a scripted-input test GPF here instead of publishing')
    parser.add_argument('--test-syms', type=Path, help='with --test-gpf: the stub symbols as Tcl (set ::sym(..)), '
                                                       'and the stub itself beside it (.bin)')
    parser.add_argument('--syms', type=Path, help="also write the release stub's symbols as Tcl, for the rig")
    args = parser.parse_args()
    if args.test_gpf:
        test_build(args.assembler, args.engine_dir, args.test_gpf, args.test_syms)
        return
    stub, symbols = assemble(args.assembler, args.engine_dir, False, HERE / 'assets')
    (HERE / 'assets/stub.sym').unlink()
    if args.syms:
        args.syms.write_text(''.join('set ::sym(%s) 0x%04X\n' % (k, v) for k, v in sorted(symbols.items())))
    profile = make_profile(stub, symbols)
    (HERE / 'profile.json').write_text(json.dumps(profile, indent=2) + '\n', encoding='utf-8')
    gpf = patcher().gpf_bytes(profile, {'stub': stub})             # it must compile
    print(f'Profile written; stub {len(stub)} of {STUB_MAX} bytes ({STUB_LOAD:04X}h-{symbols["stubEnd"] - 1:04X}h), '
          f'bank block {symbols["MK_BLOCK"]:04X}h, {len(profile["patches"])} patches, GPF {len(gpf)} bytes')
    if args.rom:
        rom = args.rom.read_bytes()
        _, left = check_rom(rom, profile)
        print(f'ROM {args.rom.name}: CRC-32 {zlib.crc32(rom):08X}, every expected byte found, '
              + ('no bank-register write left' if not left else
                 'bank-register stores left (data, not code: check each): ' + ' '.join(f'{o:05X}h' for o in left)))


if __name__ == '__main__':
    main()
