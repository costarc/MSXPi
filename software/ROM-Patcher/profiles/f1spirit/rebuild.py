#!/usr/bin/env python3
"""Developer-only: assemble the F1 Spirit stub (PLAYNET engine + 8 KB mapper host + src/glue.asm) and write
the profile.

    python rebuild.py --assembler sjasmplus                  stub -> assets/stub.bin, profile.json
    python rebuild.py --assembler sjasmplus --rom F1SPIRIT.ROM
                                                             also check every patch's expected bytes against
                                                             the dump, and that no bank-register write is left
    python rebuild.py --assembler sjasmplus --test-gpf T.GPF --test-syms T.tcl
                                                             scripted-input test build for the two-emulator
                                                             rig: a GPF and the stub's symbols for Tcl; the
                                                             committed files are not touched

The package uses image host "mapper-ram" (documents/PLAYNET-PROTOCOLS.md, 7.3): PLAYNET release 3.
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
ROM_SHA256 = '3b9afd12b29680abb655f05d24e0970954c38e48c5ccb24227d6c710474396a7'
ROM_CRC32 = 0x12BFD3A9
BANK = 0x2000
TRANSPORT, TRANSPORT_SIZE = 0xD000, 512        # first: on the TCP/IP path it is also in MSX-DOS's page 3 (TPA top D706h, Nextor)
STUB_LOAD, STUB_MAX = 0xD200, 1792
XIRQ = TRANSPORT + 6
EXPORTED = ('PN_TICK', 'PN_IRQ', 'PN_P1', 'PN_P2', 'MK_BLOCK', 'MK_SEG2', 'MK_W0', 'MK_W1', 'MK_W2', 'MK_W3',
            'sndTick', 'isrA', 'tickSite', 'p1', 'p2', 'fk', 'rnd', 'isrEnd', 'stubEnd')

# The 8 KB window each bank runs in (the bank-select routines at 4418h-4459h: banks n, n+1, n+2 in W1-W3; the pairs of
# 4447h/4457h for W2 and W3 only)
WINDOW_OF_BANK = {0: 0x4000, 1: 0x6000, 4: 0x6000, 7: 0x6000, 10: 0x6000, 13: 0x6000,
                  2: 0x8000, 5: 0x8000, 8: 0x8000, 11: 0x8000, 14: 0x8000,
                  3: 0xA000, 6: 0xA000, 9: 0xA000, 12: 0xA000, 15: 0xA000}
BANK_REGISTERS = {0x5000: 'MK_W0', 0x7000: 'MK_W1', 0x9000: 'MK_W2', 0xB000: 'MK_W3'}

# Every ld (nn),a to a bank register, as (CPU address, register): all of them in bank 0 (4000h-5FFFh, fixed). The
# sound driver's two SCC enables (bank 13, 6DA5h/6DACh/6E06h/6E1Fh) are in code that SCC_RETS removes.
BANK_SWITCHES = [
    (0x402F, 0x7000), (0x4037, 0x9000), (0x403F, 0xB000), (0x404B, 0x7000), (0x404F, 0x9000), (0x4053, 0xB000),
    (0x406D, 0xB000), (0x4073, 0x9000), (0x4079, 0x7000), (0x42C7, 0x7000), (0x42CF, 0x9000), (0x42D7, 0xB000),
    (0x42E7, 0xB000), (0x42ED, 0x9000), (0x42F3, 0x7000), (0x4405, 0x7000), (0x440A, 0x9000), (0x4410, 0xB000),
    (0x4420, 0x7000), (0x4426, 0x9000), (0x442C, 0xB000), (0x444B, 0x9000), (0x4452, 0xB000), (0x445B, 0xB000),
]

# Konami SCC sound: in RAM there is no SCC, and its registers (9800h-98FFh, enabled by 3Fh in 9000h) would be
# written into the bank copies. The sound driver's SCC writes go (bank 13): one register write (called from 6CE9h
# and 6DB0h) and the waveform upload from 6E04h. Its PSG part stays.
SCC_RETS = [(13, 0x6DA1, '7e', 'one SCC register write (callers at 6CF9h-6D21h and 6D88h-6D9Dh)'),
            (13, 0x6E04, '3e', 'SCC waveform upload (from 6DC3h-6DEFh)')]

# ld a,r and the instruction after it -> call to the glue's deterministic version
LD_A_R = [(1, 0x7327, 'ed5f0f', 'rRrca'), (2, 0x9021, 'ed5f0f', 'rRrca')]

# Pairs the loader builds. Page 1: all five the game uses (W0 is always bank 0). Page 2: the five on the diagonal are
# pinned and are the homes of the banks with page 1's five; the others follow, the combinations of W2 (2 5 8 11 14)
# with W3 (3 6 9 12 15). The loader builds as many as the machine has segments for.
PAGE1_PAIRS = [(0, 1), (0, 4), (0, 7), (0, 10), (0, 13)]
PAGE2_PAIRS = [(2, 3), (5, 6), (8, 9), (11, 12), (14, 15)] + [
    (w2, w3) for w2 in (2, 5, 8, 11, 14) for w3 in (3, 6, 9, 12, 15) if (w2, w3) not in
    ((2, 3), (5, 6), (8, 9), (11, 12), (14, 15))]
PINNED = (5, 5)
MIN_SEGMENTS, RECOMMENDED_SEGMENTS = 16, 32


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

    # The handler and the frame (all in bank 0, fixed at 4000h-5FFFh)
    patch(0, 0x410F, '1840', word(XIRQ), "H.KEYI hook (ld hl,4018h at 410Eh) -> the transport's XIRQ, which jumps to 4018h")
    patch(0, 0x402A, '21f1f0', b'\xc3' + word('isrA'),
          'Interrupt, busy flag set: count it (PN_IRQ), the deferred screen update, on at 407Dh; the sound, its queue and '
          'the countdown move to sndTick')
    patch(0, 0x40A4, 'cd3543', b'\xcd' + word('tickSite'), 'TICK site: the input reader, once per frame -> PN_TICK, then the reader')
    patch(0, 0x40B0, '21c5e1cb86', b'\xcd' + word('isrEnd') + bytes(2),
          'The frame catch-up: the frame flag cleared, or the next frame at once when an interrupt went by during '
          'PN_TICK -> isrEnd')
    patch(0, 0x4281, 'cd6743', b'\xcd' + word('p1'), "The title's menu: player 1 (the inviter)")
    patch(0, 0x4335, 'cdd143', b'\xcd' + word('fk'), 'Function keys (pause ...) from either player')
    patch(0, 0x4344, 'cd6743', b'\xcd' + word('p1'), "Player 1's pad: player 1's input")
    patch(0, 0x4350, 'cd9443', b'\xcd' + word('p2'), "Player 2's pad: player 2's input")
    patch(3, 0xB3A9, 'af57', bytes([0x37, 0xc9]), 'The password keyboard scan: no key (scf, ret)')
    for bank, cpu, expected, routine in LD_A_R:
        patch(bank, cpu, expected, b'\xcd' + word(routine) + bytes(len(expected) // 2 - 3),
              f'ld a,r -> {routine}, deterministic')
    for cpu, register in BANK_SWITCHES:
        name = BANK_REGISTERS[register]
        patch(0, cpu, '32' + word(register).hex(), b'\xcd' + word(name), f'ld ({register:04X}h),a -> {name}')
    for bank, cpu, expected, what in SCC_RETS:
        patch(bank, cpu, expected, b'\xc9', f'SCC: ret, {what}')
    patches.sort(key=lambda p: p['offset'])
    return patches


def make_profile(stub, symbols):
    return {
        'format': 'msxpi-rom-patch', 'version': 2, 'id': 'f1spirit-msxpi-netplay-v1',
        'abi': ['msxpi-netplay-v1'],
        'source': {'size': ROM_SIZE, 'sha256': ROM_SHA256, 'crc32': ROM_CRC32, 'file': 'F1SPIRIT.ROM'},
        'output': {'size': ROM_SIZE, 'fill': 0, 'mapper': 'konami-scc', 'target': 'ram-image'},
        'requirements': ["The player's own F1SPIRIT.ROM: Konami's F1 Spirit (MSX, 1987), 128 KB, the dump identified above",
                         'PLAYNET release 3, over an MSXPi or over TCP/IP UNAPI',
                         f'A memory mapper with at least {MIN_SEGMENTS} free 16 KB segments for the game '
                         f'(512 KB recommended: {RECOMMENDED_SEGMENTS} segments play without pauses)'],
        'assets': {'stub': {'file': 'assets/stub.bin', 'sha256': hashlib.sha256(stub).hexdigest()}},
        'layout': [{'source': 'input', 'offset': 0, 'size': ROM_SIZE, 'destination': 0}],
        'patches': make_patches(symbols),
        'netplay': {
            'abi': 'msxpi-netplay-v1', 'game_id': 'f1spirit', 'title': 'F1 Spirit (2 players)', 'roles': ['P1', 'P2'],
            'transport': 'lockstep', 'input_bytes': 2,
            'image': {'host': 'mapper-ram', 'mapper': 'konami-scc', 'bank_size': BANK, 'banks': ROM_SIZE // BANK,
                      'block': symbols['MK_BLOCK'], 'start_banks': [0, 1, 2, 3],
                      'page1_pairs': [list(p) for p in PAGE1_PAIRS], 'page2_pairs': [list(p) for p in PAGE2_PAIRS],
                      'pinned': list(PINNED), 'min_segments': MIN_SEGMENTS,
                      'recommended_segments': RECOMMENDED_SEGMENTS},
            'stub': {'asset': 'stub', 'load': STUB_LOAD, 'max': STUB_MAX},
            'transport_area': {'address': TRANSPORT, 'size': TRANSPORT_SIZE},
            # C000h-CFFFh and E000h-F0F8h (the stack from F0F0h down): measured over ten minutes of play
            'game_ram': [[0xDA00, 0xDDFF], [0xE000, 0xF0FF]],   # DA00h-DDFFh: the bank engine's pair map
            'irq_handler': 0x4018,
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
    profile['id'] = 'f1spirit-msxpi-netplay-test'
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
    parser.add_argument('--rom', type=Path, help="the player's F1SPIRIT.ROM, to check the patches against")
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
