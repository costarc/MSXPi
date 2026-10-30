#!/usr/bin/env python3
"""Developer-only: assemble the Bubble Bobble stub (PLAYNET engine + 8 KB mapper host + src/glue.asm) and write
the profile.

    python rebuild.py --assembler sjasmplus                  stub -> assets/stub.bin, profile.json
    python rebuild.py --assembler sjasmplus --rom BUBBLE.ROM
                                                             also check every patch's expected bytes against
                                                             the dump, and that no bank-register write is left
    python rebuild.py --assembler sjasmplus --test-gpf T.GPF --test-syms T.tcl
                                                             scripted-input test build for the two-emulator
                                                             rig: a GPF and the stub's symbols for Tcl; the
                                                             committed files are not touched

The package uses image host "mapper-ram" (profiles/bubble/README.md): PLAYNET release 3.
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
ROM_SHA256 = '15962fd815c3fd8d28cbb664c8f99d10825979fb5b9bd975b7aac785d35532eb'
ROM_CRC32 = 0x6524D9FC
BANK = 0x2000
TRANSPORT, TRANSPORT_SIZE = 0xC950, 512        # C950h-CB4Fh: above the task stacks (C000h-C94Fh), below the pair map
STUB_LOAD, STUB_MAX = 0xE660, 0xEF80 - 0xE660  # E660h-EF7Fh: the game never writes there after INIT
MK_MAP = 0xCC00                                # the bank engine's pair map, CC00h-CFFFh
XIRQ = TRANSPORT + 6
IRQ_HANDLER = 0x42D5                           # the game's H.KEYI handler: the whole game runs in it
EXPORTED = ('PN_TICK', 'PN_IRQ', 'PN_P1', 'PN_P2', 'MK_BLOCK', 'MK_SEG2', 'MK_W1', 'MK_W2', 'MK_W3', 'MK_W23',
            'inP1', 'inP2', 'stopKey', 'stubInit', 'busyChk', 'isrEnd', 'clrGame', 'sndMap', 'gameMap', 'rnd', 'stubEnd')

BANK_REGISTERS = {0x6FF8: 'MK_W1', 0x77F8: 'MK_W2', 0x7FF8: 'MK_W3'}   # ASCII8: 6800h-6FFFh W1, 7000h W2, 7800h W3

# ld a,r and the instruction after it -> the glue's deterministic version: (bank, offset in the bank, bytes, routine).
# Two more ED 5F in bank 2 (05128h, 055C8h) are graphics data.
LD_A_R = [(4, 0x117D, 'ed5fe601', 'rAnd01'), (4, 0x1564, 'ed5fe63f', 'rAnd3F'), (4, 0x1B75, 'ed5fe607', 'rAnd07'),
          (4, 0x1BAD, 'ed5fe60f', 'rAnd0F'), (5, 0x1974, 'ed5fac', 'rXorH'), (5, 0x1978, 'ed5fad', 'rXorL'),
          (7, 0x1E5D, 'ed5f80', 'rAddB'), (7, 0x1FB2, 'ed5f81', 'rAddC'), (9, 0x1637, 'ed5fe67f', 'rnd'),
          (9, 0x1A2B, 'ed5fe610', 'rAnd10'), (9, 0x1A30, 'ed5fe603', 'rAnd03'), (13, 0x0E49, 'ed5fad', 'rXorL'),
          (13, 0x1805, 'ed5fe607', 'rAnd07'), (13, 0x18B0, 'ed5fe607', 'rAnd07'), (15, 0x0D3D, 'ed5f81', 'rAddC')]

# Pairs the loader builds. Page 1: W0 is always bank 0, W1 bank 4 or 11. Page 2 (W2, W3), as measured: the first
# twelve are pinned and are the homes of every bank not in page 1, then the other pairs seen in play.
PAGE1_PAIRS = [(0, 4), (0, 11)]
PAGE2_PAIRS = [(9, 5), (14, 15), (9, 3), (9, 13), (9, 15), (6, 5), (6, 10), (2, 1), (8, 5), (9, 7), (12, 13), (14, 5),
               (6, 13), (9, 2), (9, 10), (12, 5), (2, 3), (2, 5), (9, 1), (0, 13)]      # MK_P2_MAX (glue.asm) >= 20
PINNED = (2, 12)
MIN_SEGMENTS, RECOMMENDED_SEGMENTS = 16, 22


def offset(bank, o):
    assert 0 <= o < BANK
    return bank * BANK + o


# Every ld (6FF8h/77F8h/7FF8h),a of the game, as (ROM offset, window 1-3), except the handler's four at
# 42EAh-4302h (sndMap, gameMap). Each one sits next to the game's shadow copy (ld (E488h-E48Ah),a, or ld a,(E489h/E48Ah) before it).
BANK_SWITCHES = [
    (0x0006D, 1), (0x0007E, 3), (0x00089, 2), (0x0009C, 3), (0x000A4, 2), (0x000F4, 3), (0x00108, 2), (0x00110, 3),
    (0x0015D, 3), (0x00169, 3), (0x00172, 3), (0x0017D, 3), (0x001A6, 3), (0x001AE, 2), (0x001CE, 3), (0x001D6, 2),
    (0x0045C, 3), (0x00467, 3), (0x01129, 2), (0x011A9, 1), (0x011B1, 2), (0x011B9, 3),
    (0x011C4, 1), (0x011CC, 2), (0x011D4, 3), (0x01208, 3), (0x01213, 3), (0x013B5, 3), (0x013C0, 3), (0x01511, 3),
    (0x0151C, 3), (0x0152A, 3), (0x01535, 3), (0x015CE, 2), (0x08143, 2), (0x0814B, 3), (0x0816C, 2), (0x08174, 3),
    (0x08193, 2), (0x0819E, 2), (0x08227, 2), (0x0822F, 3), (0x08323, 2), (0x0832B, 3), (0x083BA, 2), (0x083C2, 3),
    (0x084D6, 2), (0x084E1, 2), (0x08523, 2), (0x08569, 2), (0x0876D, 3), (0x08778, 3), (0x08A5D, 3), (0x08A78, 3),
    (0x08AD3, 3), (0x08B56, 3), (0x08B63, 3), (0x08C6D, 3), (0x08C78, 3), (0x08CF7, 3), (0x08D02, 3), (0x08E55, 3),
    (0x08E71, 3), (0x0901A, 3), (0x09025, 3), (0x09A97, 3), (0x09AA2, 3), (0x09AC1, 3), (0x09ACC, 3), (0x09CE4, 2),
    (0x09CFE, 2), (0x0B751, 2), (0x0B858, 2), (0x0B867, 2), (0x0B8C6, 2), (0x0BECC, 2), (0x0BED5, 2), (0x0BF0B, 2),
    (0x126FD, 3), (0x12708, 3), (0x12728, 3), (0x1273F, 3), (0x1278A, 3), (0x12795, 3), (0x127C7, 3), (0x127D2, 3),
    (0x1280E, 3), (0x12819, 3), (0x128DB, 3), (0x128E9, 3), (0x1290B, 3), (0x12916, 3), (0x12963, 3), (0x1296E, 3),
    (0x135DA, 3), (0x135E5, 3), (0x1365F, 3), (0x1366A, 3), (0x13673, 3), (0x1367F, 3), (0x13736, 3), (0x13741, 3),
    (0x13884, 3), (0x13892, 3), (0x1389B, 3), (0x138A9, 3), (0x138B2, 3), (0x138BD, 3), (0x138C6, 3), (0x138D1, 3),
    (0x138DA, 3), (0x138E5, 3), (0x138EE, 3), (0x138F9, 3), (0x13914, 3), (0x1391F, 3), (0x13964, 3), (0x1396F, 3),
    (0x13978, 3), (0x13983, 3), (0x1398F, 3), (0x13998, 3), (0x139A3, 3), (0x139D0, 3), (0x139DC, 3), (0x139E8, 3),
    (0x13B77, 3), (0x13B82, 3), (0x13BB4, 3), (0x13BBF, 3), (0x13C16, 3), (0x13C25, 3), (0x13C4F, 3), (0x13C5B, 3),
    (0x13C74, 3), (0x13C7F, 3), (0x13D13, 3), (0x13D1E, 3), (0x13D96, 3), (0x13DA1, 3), (0x13DC1, 3), (0x13DCC, 3),
    (0x13DDE, 3), (0x13DE9, 3), (0x13E08, 3), (0x13E13, 3), (0x13E32, 3), (0x13E3D, 3), (0x13E99, 3), (0x13EBD, 3),
    (0x13EDC, 3), (0x13EE7, 3), (0x13F05, 3), (0x13F10, 3), (0x13F19, 3), (0x13F24, 3), (0x13F9C, 3), (0x13FA7, 3),
    (0x13FB0, 3), (0x13FC0, 3), (0x13FC9, 3), (0x13FD7, 3), (0x13FEC, 3),
]


def sites_asm():
    """src/sites.asm: the stub's table of bank-switch sites (glue.asm, stubInit), per bank."""
    lines = ['; Generated by rebuild.py from BANK_SWITCHES: per bank, "defb bank, count", then count words',
             '; (register 1-3 << 13 | offset in the bank). FFh ends the table.']
    for bank in range(ROM_SIZE // BANK):
        words = [window << 13 | (o % BANK) for o, window in BANK_SWITCHES if o // BANK == bank]
        if not words:
            continue
        lines.append(f'        defb    {bank}, {len(words)}')
        for i in range(0, len(words), 8):
            lines.append('        defw    ' + ', '.join(f'${w:04X}' for w in words[i:i + 8]))
    lines.append('        defb    $FF')
    return chr(10).join(lines) + chr(10)


def assemble(assembler, engine_dir, scripted, out_dir):
    """Build the stub into out_dir: returns (bytes, symbols)."""
    src = HERE / 'src'
    (src / 'sites.asm').write_text(sites_asm())
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

    def patch(o, expected, replacement, reason):
        bank, cpu = divmod(o, BANK)
        patches.append({'offset': o, 'expected': bytes.fromhex(expected).hex(), 'replace': replacement.hex(),
                        'reason': f'{o:05X}h (bank {bank} + {cpu:04X}h): {reason}'})

    def call(name, length):
        return bytes([0xCD]) + word(name) + bytes(length - 3)

    # INIT (4054h): before the game's first bank switch, the stub patches the 163 sites in every built segment
    patch(0x005A, 'cd8441', call('stubInit', 3), 'INIT: call 4184h -> stubInit: the bank switches -> MK_W1..MK_W3 in every segment, then 4184h')
    # INIT: the game clears C000h-F37Dh; the stub, the transport and the pair map are there
    patch(0x0079, 'cd2568', call('clrGame', 3), 'INIT: the RAM clear (6825h, C000h-F37Dh) -> clrGame: the same around the stub, the transport and the pair map')
    # The H.KEYI hook: ld hl,42D5h at 413Ch
    patch(0x013D, 'd542', word(XIRQ), "H.KEYI -> the transport's XIRQ, which jumps to the handler 42D5h")
    # The handler's busy check and its end: an interrupt that came during the exchange runs the next frame at once
    patch(0x02DD, '3a32d0a7203b', call('busyChk', 6), 'the handler is busy -> busyChk: drop the interrupt, or keep it for later if it came during PN_TICK')
    patch(0x031A, 'af3232d0', bytes([0xC3]) + word('isrEnd') + bytes(1), 'the end of the handler -> isrEnd: the next frame now if one is pending')
    # The handler's own bank switches: the sound driver's banks 14 and 15, then back from the shadows; each in one switch
    patch(0x02E8, '3e0e32f8773e0f32f87f', call('sndMap', 10), 'the handler maps banks 14/15 for the sound driver -> sndMap (MK_W23)')
    patch(0x02F9, '3a89e432f8773a8ae432f87f', call('gameMap', 12), 'the handler puts back W2/W3 from E489h/E48Ah -> gameMap (MK_W23)')
    # The input reader 4323h, once per interrupt: the TICK
    patch(0x032F, '1e8fcd53434fcd6443b1', call('inP1', 10), 'player 1 (joystick 1 + keys) -> inP1: PN_TICK, then player 1 (seat 0)')
    patch(0x0342, '1ecfcd53434fcdb343b1', call('inP2', 10), 'player 2 (joystick 2 + keys) -> inP2: player 2 (seat 1)')
    # Bank 13: the pause key (STOP) and two key combinations, read from the keyboard
    patch(offset(13, 0x108D), 'cd4101', call('stopKey', 3), "the pause: STOP (row 7) -> stopKey, either player's from the inputs")
    patch(offset(13, 0x10BD), 'cd4101', call('stopKey', 3), 'the pause: STOP released -> stopKey')
    patch(offset(13, 0x1099), 'cd4101', bytes.fromhex('3eff00'), 'HOME+INS / HOME+DEL (row 8) are local keys: never pressed')
    for bank, o, expected, routine in LD_A_R:
        patch(offset(bank, o), expected, call(routine, len(expected) // 2), f'ld a,r -> {routine}, deterministic')
    patches.sort(key=lambda p: p['offset'])
    return patches


def make_profile(stub, symbols):
    return {
        'format': 'msxpi-rom-patch', 'version': 2, 'id': 'bubble-msxpi-netplay-v1',
        'abi': ['msxpi-netplay-v1'],
        'source': {'size': ROM_SIZE, 'sha256': ROM_SHA256, 'crc32': ROM_CRC32, 'file': 'BUBBLE.ROM'},
        'output': {'size': ROM_SIZE, 'fill': 0, 'mapper': 'ascii8', 'target': 'ram-image'},
        'requirements': ["The player's own BUBBLE.ROM: Taito's Bubble Bobble for the MSX2, 128 KB, the dump identified above",
                         'An MSX2 (the game needs one), PLAYNET release 3',
                         f'A memory mapper with at least {MIN_SEGMENTS} free 16 KB segments for the game '
                         f'(512 KB recommended: {RECOMMENDED_SEGMENTS} segments play without pauses)'],
        'assets': {'stub': {'file': 'assets/stub.bin', 'sha256': hashlib.sha256(stub).hexdigest()}},
        'layout': [{'source': 'input', 'offset': 0, 'size': ROM_SIZE, 'destination': 0}],
        'patches': make_patches(symbols),
        'netplay': {
            'abi': 'msxpi-netplay-v1', 'game_id': 'bubble', 'title': 'Bubble Bobble (2P co-op)', 'roles': ['P1', 'P2'],
            'transport': 'lockstep', 'input_bytes': 1,
            'image': {'host': 'mapper-ram', 'mapper': 'ascii8', 'bank_size': BANK, 'banks': ROM_SIZE // BANK,
                      'block': symbols['MK_BLOCK'], 'start_banks': [0, 4, 9, 5],
                      'page1_pairs': [list(p) for p in PAGE1_PAIRS], 'page2_pairs': [list(p) for p in PAGE2_PAIRS],
                      'pinned': list(PINNED), 'min_segments': MIN_SEGMENTS,
                      'recommended_segments': RECOMMENDED_SEGMENTS},
            'stub': {'asset': 'stub', 'load': STUB_LOAD, 'max': STUB_MAX},
            'transport_area': {'address': TRANSPORT, 'size': TRANSPORT_SIZE},
            # measured over ten minutes of two-player play (profiles/bubble/README.md); CC00h-CFFFh: the pair map
            'game_ram': [[0xC000, TRANSPORT - 1], [MK_MAP, STUB_LOAD - 1], [STUB_LOAD + STUB_MAX, 0xF37F]],
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
    registers = {1: 0x6FF8, 2: 0x77F8, 3: 0x7FF8}
    for o, window in BANK_SWITCHES:                # what stubInit does at run time
        assert out[o:o + 3] == bytes([0x32]) + struct.pack('<H', registers[window]), f'bank switch site {o:05X}h'
        out[o:o + 3] = bytes([0xCD]) + struct.pack('<H', profile['symbols'][f'MK_W{window}'])
    left = []
    for o in range(len(out) - 2):                  # the ASCII8 registers this game writes: xxF8h in 6800h-7FFFh
        if out[o] == 0x32 and (out[o + 1] | out[o + 2] << 8) in registers.values():
            left.append(o)
    homes = {b for pair in PAGE1_PAIRS[:PINNED[0]] + PAGE2_PAIRS[:PINNED[1]] for b in pair}
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
    profile['id'] = 'bubble-msxpi-netplay-test'
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
    parser.add_argument('--rom', type=Path, help="the player's BUBBLE.ROM, to check the patches against")
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
