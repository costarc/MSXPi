#!/usr/bin/env python3
"""Developer-only: assemble the 1942 stub (PLAYNET engine + 8 KB mapper host + src/glue.asm) and write
the profile.

    python rebuild.py --assembler sjasmplus                  stub -> assets/stub.bin, profile.json
    python rebuild.py --assembler sjasmplus --rom 1942.ROM
                                                             also check every patch's expected bytes against
                                                             the dump, and that no bank-register write is left
    python rebuild.py --assembler sjasmplus --test-gpf T.GPF --test-syms T.tcl
                                                             scripted-input test build for the two-emulator
                                                             rig: a GPF and the stub's symbols for Tcl; the
                                                             committed files are not touched

The package uses image host "mapper-ram" (documents/1942-DESIGN.md): PLAYNET release 3.
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
ROM_SHA256 = 'd8442d2c08958f0bc9be7d2078e3cf07224e1ec3493ddce3215ed8df2bd37b1f'
ROM_CRC32 = 0xC99E5601
BANK = 0x2000
TRANSPORT, TRANSPORT_SIZE = 0xDD60, 512        # DD60h-DF5Fh: the game owns C000h-DD5Fh, the free area is DD60h-DFFFh and E017h-E9FFh
STUB_LOAD, STUB_MAX = 0xE018, 0xE600 - 0xE018  # then the bank engine's pair map, E600h-E9FFh
XIRQ = TRANSPORT + 6
IRQ_HANDLER = 0x413E                           # a RET in bank 0: the game has no interrupt handler of its own
EXPORTED = ('PN_TICK', 'PN_IRQ', 'PN_P1', 'PN_P2', 'MK_BLOCK', 'MK_SEG2', 'MK_W0', 'MK_W1', 'MK_W2', 'MK_W3',
            'inP1', 'inAct', 'inAny', 'keyAct', 'initGame', 'rnd', 'stubEnd')

# The 8 KB window each patched bank runs in. Banks 0 and 1 are in W0 and W1 for good (the game writes the W0 and W1
# registers once, at INIT); bank 2 is the W2 bank most of the time.
WINDOW_OF_BANK = {0: 0x4000, 1: 0x6000, 2: 0x8000}
BANK_REGISTERS = {0x7000: 'MK_W2', 0x7800: 'MK_W3'}      # ASCII8: 6000h W0, 6800h W1, 7000h W2, 7800h W3

# Every ld (nn),a to the W2 or W3 register, as (bank, CPU address, register). The sites mapper_detect.py finds;
# the four at INIT (4014h-4022h) go with the INIT patch.
BANK_SWITCHES = [
    (0, 0x46C1, 0x7000), (0, 0x46C6, 0x7800), (0, 0x46F2, 0x7000), (0, 0x46F7, 0x7800), (0, 0x5128, 0x7800),
    (0, 0x544D, 0x7800), (0, 0x5DF0, 0x7800), (0, 0x5E8C, 0x7800), (1, 0x6869, 0x7800), (1, 0x718A, 0x7800),
    (2, 0x9B96, 0x7800), (2, 0x9BB6, 0x7800), (2, 0x9BD6, 0x7800), (2, 0x9D1C, 0x7800),
]

# ld a,r and the instruction after it (all in bank 1) -> call to the glue's deterministic version
LD_A_R = [(0x6100, 'ed5fe67f', 'rAnd7F'), (0x6127, 'ed5fe67f', 'rAnd7F'), (0x63A2, 'ed5f1f', 'rRra'),
          (0x63AF, 'ed5fe60c', 'rAnd0C'), (0x63D1, 'ed5fe63f', 'rAnd3F'), (0x63D8, 'ed5f1f', 'rRra'),
          (0x64F0, 'ed5fe60f', 'rAnd0F'), (0x65D5, 'ed5f1f', 'rRra'), (0x6673, 'ed5f1f', 'rRra'),
          (0x6912, 'ed5fe60f', 'rAnd0F')]

# The game's input readers are called from 5 places (6D09h) and 2 (6DAAh), all in bank 0: (CPU address, routine)
INPUT_CALLS = [(0x4161, 'cd096d', 'inAct', 'the frame'), (0x43E2, 'cd096d', 'inAct', 'pause: until the key is released'),
               (0x43EC, 'cd096d', 'inAct', 'pause: until a key is pressed'), (0x4468, 'cd096d', 'inP1', 'the title menu: player 1, the inviter'),
               (0x4507, 'cd096d', 'inAny', 'the game over wait: anyone'),
               (0x459E, 'cdaa6d', 'keyAct', 'hi-score name entry'), (0x45B7, 'cdaa6d', 'keyAct', 'hi-score name entry')]

# Pairs the loader builds. Page 1 is always (0,1). Page 2: the first twelve are pinned and are the homes of banks 2-15
# (the game only ever has bank 2 or 5 in W2, so every other bank needs a pair of its own); then the pairs seen in play,
# then the ones that could come. The loader builds as many as the machine has segments for.
PAGE1_PAIRS = [(0, 1)]
PAGE2_PAIRS = [(2, 3), (5, 4), (5, 6), (5, 7), (2, 8), (2, 9), (2, 10), (2, 11), (2, 12), (2, 13), (2, 14), (2, 15),
               (2, 4), (2, 6), (2, 7), (5, 3), (5, 8), (5, 9), (5, 10), (5, 11), (5, 12), (5, 13), (5, 14), (5, 15)]
PINNED = (1, 12)
MIN_SEGMENTS, RECOMMENDED_SEGMENTS = 20, 28


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

    # INIT (4013h): the game writes the four bank registers, then sets up. The loader has mapped the start banks.
    patch(0, 0x4014, '320060' '3c' '320068' '3c' '320070' '3c' '320078', b'\xcd' + word('initGame') + bytes(12),
          'INIT: the four bank-register writes -> clear the game RAM, SP = F380h, H.KEYI -> XIRQ (initGame)')
    patch(0, 0x5CD5, '3600', bytes(2), 'INIT: ld (4000h),0 (the ldir after it is already gone): a write into the ROM copy')
    # The input readers: every call is a TICK
    for cpu, expected, routine, what in INPUT_CALLS:
        patch(0, cpu, expected, b'\xcd' + word(routine), f'input {what} -> {routine}: PN_TICK, then the net input')
    patch(1, 0x6D73, 'cd776d', bytes(3), 'The secret key combination (6D77h) is not read: it is local')
    for cpu, expected, routine in LD_A_R:
        patch(1, cpu, expected, b'\xcd' + word(routine) + bytes(len(expected) // 2 - 3),
              f'ld a,r -> {routine}, deterministic')
    for bank, cpu, register in BANK_SWITCHES:
        name = BANK_REGISTERS[register]
        patch(bank, cpu, '32' + word(register).hex(), b'\xcd' + word(name), f'ld ({register:04X}h),a -> {name}')
    patches.sort(key=lambda p: p['offset'])
    return patches


def make_profile(stub, symbols):
    return {
        'format': 'msxpi-rom-patch', 'version': 2, 'id': '1942-msxpi-netplay-v1',
        'abi': ['msxpi-netplay-v1'],
        'source': {'size': ROM_SIZE, 'sha256': ROM_SHA256, 'crc32': ROM_CRC32, 'file': '1942.ROM'},
        'output': {'size': ROM_SIZE, 'fill': 0, 'mapper': 'ascii8', 'target': 'ram-image'},
        'requirements': ["The player's own 1942.ROM: ASCII's 1942 for the MSX, 128 KB, the dump identified above",
                         'PLAYNET release 3, over an MSXPi or over TCP/IP UNAPI',
                         f'A memory mapper with at least {MIN_SEGMENTS} free 16 KB segments for the game '
                         f'(512 KB recommended: {RECOMMENDED_SEGMENTS} segments play without pauses)'],
        'assets': {'stub': {'file': 'assets/stub.bin', 'sha256': hashlib.sha256(stub).hexdigest()}},
        'layout': [{'source': 'input', 'offset': 0, 'size': ROM_SIZE, 'destination': 0}],
        'patches': make_patches(symbols),
        'netplay': {
            'abi': 'msxpi-netplay-v1', 'game_id': '1942', 'title': '1942 (turn based)', 'roles': ['P1', 'P2'],
            'transport': 'lockstep', 'input_bytes': 2,
            'image': {'host': 'mapper-ram', 'mapper': 'ascii8', 'bank_size': BANK, 'banks': ROM_SIZE // BANK,
                      'block': symbols['MK_BLOCK'], 'start_banks': [0, 1, 2, 3],
                      'page1_pairs': [list(p) for p in PAGE1_PAIRS], 'page2_pairs': [list(p) for p in PAGE2_PAIRS],
                      'pinned': list(PINNED), 'min_segments': MIN_SEGMENTS,
                      'recommended_segments': RECOMMENDED_SEGMENTS},
            'stub': {'asset': 'stub', 'load': STUB_LOAD, 'max': STUB_MAX},
            'transport_area': {'address': TRANSPORT, 'size': TRANSPORT_SIZE},
            # C000h-CFFFh and E000h-F0F8h (the stack from F0F0h down): measured over ten minutes of play
            'game_ram': [[0xC000, 0xDD5F], [0xE000, 0xE016], [0xE600, 0xF37F]],   # E600h-E9FFh: the bank engine's pair map
            'irq_handler': IRQ_HANDLER,
            'start': 'header-init',
            'min_playnet': 3, 'requires': ['mapper-ram']},
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
        if out[o] == 0x32 and (out[o + 1] | out[o + 2] << 8) in (0x6000, 0x6800, 0x7000, 0x7800):
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
    profile['id'] = '1942-msxpi-netplay-test'
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
    parser.add_argument('--rom', type=Path, help="the player's 1942.ROM, to check the patches against")
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
