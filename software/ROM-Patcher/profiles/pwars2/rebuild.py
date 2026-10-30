#!/usr/bin/env python3
"""Developer-only: assemble the Penguin-kun Wars 2 stub (PLAYNET engine + ASCII16 mapper host + src/glue.asm)
and write the profile.

    python rebuild.py --assembler sjasmplus                  stub -> assets/stub.bin, profile.json
    python rebuild.py --assembler sjasmplus --rom P-WARS2.ROM
                                                             also check every patch's expected bytes against
                                                             the dump, and that no bank select is left
    python rebuild.py --assembler sjasmplus --test-gpf T.GPF --test-syms T.tcl
                                                             scripted-input test build for the two-emulator
                                                             rig: a GPF and the stub's symbols for Tcl; the
                                                             committed files are not touched
    python rebuild.py --assembler sjasmplus --rom P-WARS2.ROM --local-rom OUT.ROM --local-stub OUT.BIN
                                                             test build without the network: the patched ROM to
                                                             run as an ASCII16 cartridge in openMSX, and the stub
                                                             the test's Tcl puts at A800h at INIT (player 2 on
                                                             joystick 2)

The package uses image host "mapper-ram" with mapper type ascii16 (documents/PWARS2-DESIGN.md): PLAYNET
release 3. The engine and the mapper host are copied from software/Client/src/playnet/engine/ into src/.
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
ENGINE_FILES = ('playnet_engine.asm', 'mapper_a16.asm')

ROM_SIZE = 262144
ROM_SHA256 = '7815e5ac436521faeec24719d6edaaa820f07b8fb55ddafab4a0a08364cc766e'
ROM_CRC32 = 0xB1B24DA1
BANK16, HALF = 0x4000, 0x2000
TRANSPORT, TRANSPORT_SIZE = 0xF100, 512        # F100h-F2FFh: above the game's stack (F100h down), never written
STUB_LOAD, STUB_MAX = 0xA630, 0xAC80 - 0xA630  # page 2, the game's own RAM segment (A700h-A7FFh: see xTab)
IRQ_HANDLER = 0xBE8B                           # a RET in the game's code (B400h-): the game has no H.KEYI handler
EXPORTED = ('PN_TICK', 'PN_IRQ', 'PN_P1', 'PN_P2', 'MK_BLOCK', 'MK_A16', 'tStk', 'tTrg', 'cStk', 'cTrg',
            'tickInc', 'tickDec', 'sndTick', 'initGame', 'vsSet', 'vsFree', 'vsHold', 'vsCtl', 'rnd', 'stubEnd')

# INIT copies the ROM's 4030h-7C2Eh (bank 0) to B400h-EFFEh and runs it there: RAM address -> file offset
CODE_RAM, CODE_FILE, CODE_LEN = 0xB400, 0x0030, 0x3BFF


def ram(addr):
    assert CODE_RAM <= addr < CODE_RAM + CODE_LEN, hex(addr)
    return addr - CODE_RAM + CODE_FILE


def bank(b, cpu):
    assert 0x4000 <= cpu < 0x8000, hex(cpu)
    return b * BANK16 + cpu - 0x4000


# The readers of the joystick and the trigger, patched at their heads (3E 01 CD: ld a,1 / call): (offset, routine)
READERS = [(ram(0xC753), 'tTrg', 'C753h: trigger'), (ram(0xC764), 'tStk', 'C764h: direction'),
           (ram(0xC74C), 'tStk', 'C74Ch: direction (port 1)'),
           (bank(9, 0x7C59), 'tTrg', 'bank 9 7C59h: trigger (the map)'), (bank(9, 0x7C6A), 'tStk', 'bank 9 7C6Ah: direction'),
           (bank(13, 0x79CC), 'tTrg', 'bank 13 79CCh: trigger'), (bank(13, 0x79DD), 'tStk', 'bank 13 79DDh: direction'),
           (bank(15, 0x7DE5), 'tTrg', 'bank 15 7DE5h: trigger')]
# Calls inside a frame that has its TICK at its start: this frame's value. (offset, expected, routine, what)
CACHED = [(ram(0xC21E), 'cd64c7', 'cStk', 'the penguin: direction'), (ram(0xC262), 'cd64c7', 'cStk', 'the penguin: direction'),
          (ram(0xC2C7), 'cd64c7', 'cStk', 'the penguin: direction'), (ram(0xC5D2), 'cd64c7', 'cStk', 'the penguin: direction'),
          (ram(0xC275), 'cd53c7', 'cTrg', 'the penguin: trigger'), (ram(0xC701), 'cd53c7', 'cTrg', 'the penguin: trigger'),
          (ram(0xEE76), 'cd53c7', 'cTrg', 'the throw power (H.TIMI handler)'),
          (ram(0xEE81), 'cd53c7', 'cTrg', 'the throw power (H.TIMI handler)'),
          (bank(9, 0x78FA), 'cd597c', 'cTrg', 'the map: trigger'), (bank(9, 0x7953), 'cd6a7c', 'cStk', 'the map: direction')]
# Where the game counts its frames (ld hl,B1F2h / inc or dec (hl)): the TICK of that loop
FRAMES = [(ram(0xB50C), '21f2b134', 'tickInc', 'the match'), (ram(0xB7E9), '21f2b135', 'tickDec', 'the end of a round'),
          (bank(9, 0x78E1), '21f2b135', 'tickDec', 'the map')]
# ld a,r and the instruction next to it -> the glue's deterministic version: (offset, expected, routine)
LD_A_R = [(ram(0xE19B), '47ed5f', 'rndB'), (bank(7, 0x7B89), '47ed5f', 'rndB'), (bank(12, 0x7F2E), '47ed5f', 'rndB'),
          (bank(9, 0x7C7F), 'ed5f84', 'rAddH'), (bank(9, 0x7C85), 'ed5f85', 'rAddL'), (bank(10, 0x7ECB), 'ed5f81', 'rAddC')]
# The opponent's AI, player 2's in versus: (offset, expected, replacement opcode, routine, what)
VERSUS = [(ram(0xCA7D), '3af6b1', 0xCD, 'vsSet', "the opponent's frame: player 2 controls it"),
          (ram(0xCB00), 'cd55cc', 0xCD, 'vsMvG', 'the step: not in the states player 2 moves in'),
          (ram(0xCB07), 'cabfd0', 0xCA, 'vsFree', 'state 0 (pick a ball)'),
          (ram(0xCB11), 'ca2ad1', 0xCA, 'vsFree', 'state 20h (walk to it)'),
          (ram(0xCB16), 'cae1d1', 0xCA, 'vsHold', 'state 30h (hold it, throw)'),
          (ram(0xCB55), 'cd7fcb', 0xCD, 'aiOpp', 'two opponents: the second keeps the AI'),
          (ram(0xCBA4), 'cd55cc', 0xCD, 'vsMvG', 'two opponents: the step'),
          (ram(0xCBAB), 'cabfd0', 0xCA, 'vsFree', 'two opponents: state 0'),
          (ram(0xCBB0), 'ca2ad1', 0xCA, 'vsFree', 'two opponents: state 20h'),
          (ram(0xCBB5), 'cae1d1', 0xCA, 'vsHold', 'two opponents: state 30h')]

PAGE1_PAIRS = [(2 * n, 2 * n + 1) for n in range(16)]   # every 16 KB bank, each its own segment
PAGE2_PAIRS = [(0, 1)]                                     # page 2 is the game's RAM: a segment of its own
PINNED = (16, 1)
MIN_SEGMENTS = 19                                          # 16 + 1 + a spare per page (the loader's rule)


def assemble(assembler, engine_dir, defines, out_dir):
    """Build the stub into out_dir: returns (bytes, symbols)."""
    src = HERE / 'src'
    for name in ENGINE_FILES:
        shutil.copyfile(Path(engine_dir) / name, src / name)
    out_dir = Path(out_dir)
    command = [assembler] + ['-D' + d for d in defines] + ['--sym=' + str(out_dir / 'stub.sym'), 'glue.asm']
    subprocess.run(command, cwd=src, check=True)           # glue.asm writes src/stub.bin (OUTPUT)
    shutil.move(str(src / 'stub.bin'), str(out_dir / 'stub.bin'))
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

    def patch(off, expected, replacement, reason):
        b, cpu = off // BANK16, 0x4000 + off % BANK16
        where = f'{off - CODE_FILE + CODE_RAM:04X}h (RAM)' if b == 0 and CODE_FILE <= off < CODE_FILE + CODE_LEN \
            else f'{cpu:04X}h (bank {b})'
        patches.append({'offset': off, 'expected': bytes.fromhex(expected).hex(), 'replace': replacement.hex(),
                        'reason': f'{where}: {reason}'})

    patch(bank(0, 0x4011), 'cd3801', b'\xcd' + word('initGame'),
          'INIT: call RSLREG -> initGame: the RAM cleared as a cartridge finds it, then RSLREG')
    patch(ram(0xC0D3), 'f32100', b'\xc3' + word('MK_A16'),
          'the page-1 bank select (writes 6000h-6006h) -> MK_A16: the segment holding that bank')
    patch(ram(0xC165), 'edb0', bytes(2), "the copy of bank 1's table to A700h (the stub's room): xTab reads the bank")
    for off, what in ((ram(0xE1AE), 'E1AEh'), (bank(12, 0x7CE4), 'bank 12 7CE4h'), (bank(13, 0x7907), 'bank 13 7907h')):
        patch(off, '3a21b1', b'\xc3' + word('xTab'), f'{what}: the table lookup at A700h -> xTab, from bank 1')
    patch(ram(0xE699), '21ace6', b'\x21' + word('PN_IRQ'),
          'the H.TIMI hook -> PN_IRQ, which counts; the engine ticks the handler (G_SOUND_TICK)')
    patch(ram(0xB697), '3a88ef', b'\xcd' + word('sndWait'), 'the wait for a tune to end -> a TICK each time')
    patch(ram(0xBFAB), 'f3', b'\xc9', 'MSX-MUSIC / FM-PAC search -> none found (both machines play the PSG music)')
    patch(ram(0xEE8D), 'cdcdee', bytes.fromhex('f60100'),
          'the pause key (F1), read and waited on inside the interrupt handler -> never pressed')
    patch(ram(0xB460), 'cd4101', bytes.fromhex('3eff00'), 'keys 1 and 2 at the start (a stage select) -> not pressed')
    patch(bank(9, 0x7925), 'cd4101', bytes.fromhex('3eff00'), 'the map: key M -> not pressed')
    for off, routine, what in READERS:
        patch(off, '3e01cd', b'\xc3' + word(routine), f'reader {what} -> {routine}: a TICK, then player 1')
    for off, expected, routine, what in CACHED:
        patch(off, expected, b'\xcd' + word(routine), f'{what} -> {routine}: this frame\'s value')
    for off, expected, routine, what in FRAMES:
        patch(off, expected, b'\xcd' + word(routine) + b'\x00', f'the frame counter, {what} -> {routine}: the TICK')
    for off, expected, routine in LD_A_R:
        patch(off, expected, b'\xcd' + word(routine), f'ld a,r -> {routine}, deterministic')
    for off, expected, op, routine, what in VERSUS:
        patch(off, expected, bytes([op]) + word(routine), f'versus: {what} -> {routine}')
    patches.sort(key=lambda p: p['offset'])
    return patches


def make_profile(stub, symbols):
    return {
        'format': 'msxpi-rom-patch', 'version': 2, 'id': 'pwars2-msxpi-netplay-v1',
        'abi': ['msxpi-netplay-v1'],
        'source': {'size': ROM_SIZE, 'sha256': ROM_SHA256, 'crc32': ROM_CRC32, 'file': 'P-WARS2.ROM'},
        'output': {'size': ROM_SIZE, 'fill': 0, 'mapper': 'ascii16', 'target': 'ram-image'},
        'requirements': ["The player's own P-WARS2.ROM: ASCII's Penguin-kun Wars 2 for the MSX2, 256 KB, the dump "
                         'identified above',
                         'An MSX2 (the game needs one), PLAYNET release 3, over an MSXPi',
                         f'A memory mapper with at least {MIN_SEGMENTS} free 16 KB segments for the game (512 KB)'],
        'assets': {'stub': {'file': 'assets/stub.bin', 'sha256': hashlib.sha256(stub).hexdigest()}},
        'layout': [{'source': 'input', 'offset': 0, 'size': ROM_SIZE, 'destination': 0}],
        'patches': make_patches(symbols),
        'netplay': {
            'abi': 'msxpi-netplay-v1', 'game_id': 'pwars2', 'title': 'Penguin Wars 2 (versus)', 'roles': ['P1', 'P2'],
            'transport': 'lockstep', 'input_bytes': 1,
            'image': {'host': 'mapper-ram', 'mapper': 'ascii16', 'bank_size': HALF, 'banks': ROM_SIZE // HALF,
                      'block': symbols['MK_BLOCK'], 'start_banks': [0, 1, 0, 1],
                      'page1_pairs': [list(p) for p in PAGE1_PAIRS], 'page2_pairs': [list(p) for p in PAGE2_PAIRS],
                      'pinned': list(PINNED), 'min_segments': MIN_SEGMENTS, 'recommended_segments': MIN_SEGMENTS},
            'stub': {'asset': 'stub', 'load': STUB_LOAD, 'max': STUB_MAX},
            'transport_area': {'address': TRANSPORT, 'size': TRANSPORT_SIZE},
            # page 2 (the game's RAM segment) but the stub, page 3 up to the stack: measured over title, map and matches
            'game_ram': [[0x8000, STUB_LOAD - 1], [STUB_LOAD + STUB_MAX, 0xF0FF]],     # (A600h-A621h is the last)
            'irq_handler': IRQ_HANDLER,
            'start': 'header-init',
            'min_playnet': 3, 'requires': ['mapper-ram']},
        'symbols': {name: symbols[name] for name in EXPORTED}}


def check_rom(rom, profile):
    """Every expected byte is in the dump; the patched image. Also lists bank selects left (ld (6000h-77FFh),a)."""
    assert len(rom) == ROM_SIZE and hashlib.sha256(rom).hexdigest() == ROM_SHA256, 'not the dump this package is for'
    out = bytearray(rom)
    end = -1
    for p in profile['patches']:
        expected, replace = bytes.fromhex(p['expected']), bytes.fromhex(p['replace'])
        o = p['offset']
        assert o >= end, f'patches overlap at {o:05X}h'
        assert o // HALF == (o + len(expected) - 1) // HALF, f'patch at {o:05X}h crosses an 8 KB half'
        assert rom[o:o + len(expected)] == expected, f'{p["reason"]}: found {rom[o:o + len(expected)].hex()}'
        out[o:o + len(replace)] = replace
        end = o + len(expected)
    left = [o for o in range(len(out) - 2) if out[o] == 0x32 and
            ((out[o + 1] | out[o + 2] << 8) & 0xE800) in (0x6000,)]
    return out, left


def patcher():
    spec = importlib.util.spec_from_file_location('patch_rom', HERE.parents[1] / 'patch_rom.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_syms(path, symbols):
    Path(path).write_text(''.join('set ::sym(%s) 0x%04X\n' % (k, v) for k, v in sorted(symbols.items())))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--assembler', required=True, help='sjasmplus executable')
    parser.add_argument('--engine-dir', type=Path, default=ENGINE_DIR, help='PLAYNET engine sources')
    parser.add_argument('--rom', type=Path, help="the player's P-WARS2.ROM, to check the patches against")
    parser.add_argument('--test-gpf', type=Path, help='write a scripted-input test GPF here instead of publishing')
    parser.add_argument('--test-syms', type=Path, help='with --test-gpf: the stub symbols as Tcl (set ::sym(..)), '
                                                       'and the stub itself beside it (.bin)')
    parser.add_argument('--syms', type=Path, help="also write the release stub's symbols as Tcl, for the rig")
    parser.add_argument('--local-rom', type=Path, help='with --rom: the patched ROM of the no-network test build')
    parser.add_argument('--local-stub', type=Path, help='with --local-rom: its stub (for A800h) and .tcl symbols')
    args = parser.parse_args()
    if args.local_rom:
        with tempfile.TemporaryDirectory() as out:
            stub, symbols = assemble(args.assembler, args.engine_dir, ['LOCAL'], out)
        profile = make_profile(stub, symbols)
        image, _ = check_rom(args.rom.read_bytes(), profile)
        args.local_rom.write_bytes(image)
        args.local_stub.write_bytes(stub)
        write_syms(args.local_stub.with_suffix('.tcl'), symbols)
        print(f'Local test build: {args.local_rom} and stub {len(stub)} bytes at {STUB_LOAD:04X}h')
        return
    if args.test_gpf:
        with tempfile.TemporaryDirectory() as out:
            stub, symbols = assemble(args.assembler, args.engine_dir, ['SCRIPTED'], out)
        profile = make_profile(stub, symbols)
        profile['id'] = 'pwars2-msxpi-netplay-test'
        data = patcher().gpf_bytes(profile, {'stub': stub})
        args.test_gpf.write_bytes(data)
        if args.test_syms:
            write_syms(args.test_syms, symbols)
            args.test_syms.with_suffix('.bin').write_bytes(stub)
        print(f'Test GPF {args.test_gpf}: {len(data)} bytes, stub {len(stub)} bytes, '
              f'profile hash {struct.unpack_from("<I", data, 8)[0]:08x}')
        return
    stub, symbols = assemble(args.assembler, args.engine_dir, [], HERE / 'assets')
    (HERE / 'assets/stub.sym').unlink()
    if args.syms:
        write_syms(args.syms, symbols)
    profile = make_profile(stub, symbols)
    (HERE / 'profile.json').write_text(json.dumps(profile, indent=2) + '\n', encoding='utf-8')
    gpf = patcher().gpf_bytes(profile, {'stub': stub})             # it must compile
    print(f'Profile written; stub {len(stub)} of {STUB_MAX} bytes ({STUB_LOAD:04X}h-{symbols["stubEnd"] - 1:04X}h), '
          f'bank block {symbols["MK_BLOCK"]:04X}h, {len(profile["patches"])} patches, GPF {len(gpf)} bytes')
    if args.rom:
        rom = args.rom.read_bytes()
        _, left = check_rom(rom, profile)
        print(f'ROM {args.rom.name}: CRC-32 {zlib.crc32(rom):08X}, every expected byte found; '
              + ('no bank select left' if not left else
                 'ld (6000h-67FFh/7000h-77FFh),a left (data, not code: check each): ' + ' '.join(f'{o:05X}h' for o in left)))


if __name__ == '__main__':
    main()
