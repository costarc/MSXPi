#!/usr/bin/env python3
"""Developer-only: assemble the Konami's Ping Pong stub (PLAYNET engine + src/glue.asm) and write the profile.

    python rebuild.py --assembler sjasmplus                      release stub -> assets/stub.bin, profile.json
    python rebuild.py --assembler sjasmplus --rom PINGPONG.ROM   also check every patch's expected bytes against the dump
    python rebuild.py --assembler sjasmplus --test-gpf T.GPF --test-syms T.tcl
                                                                 random-pad test build for the two-emulator
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
import zlib

HERE = Path(__file__).resolve().parent
ENGINE = HERE.parents[2] / 'Client/src/playnet/engine/playnet_engine.asm'

ROM_SIZE = 16384
ROM_SHA256 = '8e0f57b2c52e85505505c1d4bb4643eb7311213676f0ecfe21dd06571fc0bbd5'
ROM_CRC32 = 0x3F200491
BASE = 0x4000
STUB_LOAD, STUB_MAX = 0xC100, 1024
TRANSPORT, TRANSPORT_SIZE = 0xC500, 512
XIRQ = TRANSPORT + 6
EXPORTED = ('PN_TICK', 'PN_IRQ', 'PN_P1', 'PN_P2', 'tickSite', 'key1', 'key2', 'forceTwo', 'rdLocal', 'stubEnd')


def assemble(assembler, engine, test, out_dir):
    """Build the stub into out_dir: returns (bytes, symbols)."""
    src = HERE / 'src'
    shutil.copyfile(engine, src / 'playnet_engine.asm')
    out_dir = Path(out_dir)
    command = [assembler] + (['-DTESTPADS'] if test else []) + [
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
                        'replace': replacement.hex(), 'reason': f'{cpu:04X}h: {reason}'})

    def word(value):
        return struct.pack('<H', symbols[value] if isinstance(value, str) else value)

    nop = b'\x00'
    patch(0x4013, '32ee40', nop * 3, 'Anti-copy write ld (40EEh),a (a RET over a DJNZ): a no-op on a cartridge, harmful in RAM')
    patch(0x4052, '22f840', nop * 3, 'Anti-copy write ld (40F8h),hl (0000h over the operand of a JP): same')
    patch(0x401D, 'cd9551', b'\xcd' + word('PN_IRQ'), 'Sound tick per interrupt -> PN_IRQ counts it; the stub ticks the driver')
    patch(0x4033, 'cde347', b'\xcd' + word('tickSite'),
          'TICK site: the pad reader, once per frame -> PN_TICK (the exchange), then the reader')
    patch(0x404A, 'fc9551', b'\xfc' + word('PN_IRQ'), 'Catch-up sound tick (an interrupt pending after the frame) -> PN_IRQ')
    patch(0x4075, '1940', word(XIRQ), "H.KEYI hook (ld hl,4019h at 4074h) -> the transport's XIRQ, which jumps to 4019h")
    patch(0x42AB, 'cd004857cd1248b2', b'\xcd' + word('key1') + nop * 5, "Menu reader: player 1's byte of this frame")
    patch(0x43A7, 'cd004857cd1248b2', b'\xcd' + word('key1') + nop * 5, "Title menu reader: player 1's byte of this frame")
    patch(0x43CD, '3202e0', b'\xcd' + word('forceTwo'), 'Title menu start: both choices are the 2 player mode')
    patch(0x47E6, 'cd004857cd1248b2', b'\xcd' + word('key1') + nop * 5, "Player 1's pad: the byte of this frame")
    patch(0x4845, 'cd024857cd5248b2', b'\xcd' + word('key2') + nop * 5, "Player 2's pad: the other player's byte of this frame")
    patches.sort(key=lambda p: p['offset'])
    return {
        'format': 'msxpi-rom-patch', 'version': 2, 'id': 'pingpong-msxpi-netplay-v1',
        'abi': ['msxpi-netplay-v1'],
        'source': {'size': ROM_SIZE, 'sha256': ROM_SHA256, 'crc32': ROM_CRC32, 'file': 'PINGPONG.ROM'},
        'output': {'size': ROM_SIZE, 'fill': 0, 'mapper': 'plain', 'target': 'ram-image'},
        'requirements': ["The player's own PINGPONG.ROM: Konami's Ping Pong (1985), 16 KB, the dump identified above",
                         'PLAYNET, over an MSXPi or over TCP/IP UNAPI (with a memory mapper)',
                         'Any MSX with 64 KB RAM on the MSXPi path'],
        'assets': {'stub': {'file': 'assets/stub.bin', 'sha256': hashlib.sha256(stub).hexdigest()}},
        'layout': [{'source': 'input', 'offset': 0, 'size': ROM_SIZE, 'destination': 0}],
        'patches': patches,
        'netplay': {
            'abi': 'msxpi-netplay-v1', 'game_id': 'pingpong', 'title': 'Konami Ping Pong', 'roles': ['P1', 'P2'],
            'transport': 'lockstep', 'input_bytes': 1,
            'image': {'host': 'plain', 'base': BASE},
            'stub': {'asset': 'stub', 'load': STUB_LOAD, 'max': STUB_MAX},
            'transport_area': {'address': TRANSPORT, 'size': TRANSPORT_SIZE},
            # E000h-E3FFh (cleared at INIT, the stack from E400h down); D500h-D5FFh as for Soccer (the start-up's stack)
            'game_ram': [[0xD500, 0xD5FF], [0xE000, 0xE4FF]],
            'irq_handler': 0x4019,
            'start': 'header-init',
            'min_playnet': 2},
        'symbols': {name: symbols[name] for name in EXPORTED}}


def check_rom(rom, profile):
    """Every expected byte is in the dump and the patches do not overlap."""
    assert len(rom) == ROM_SIZE and hashlib.sha256(rom).hexdigest() == ROM_SHA256, 'not the dump this package is for'
    end = -1
    for p in profile['patches']:
        expected = bytes.fromhex(p['expected'])
        o = p['offset']
        assert o >= end, f'patches overlap at {o:04X}h'
        assert rom[o:o + len(expected)] == expected, f'{p["reason"]}: found {rom[o:o + len(expected)].hex()}'
        end = o + len(expected)


def patcher():
    spec = importlib.util.spec_from_file_location('patch_rom', HERE.parents[1] / 'patch_rom.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_syms(path, symbols, stub):
    Path(path).write_text(''.join('set ::sym(%s) 0x%04X\n' % (k, v) for k, v in sorted(symbols.items())))
    Path(path).with_suffix('.bin').write_bytes(stub)              # the stub, for the rig's code check


def test_build(assembler, engine, gpf_path, syms_path):
    with tempfile.TemporaryDirectory() as out:
        stub, symbols = assemble(assembler, engine, True, out)
    profile = make_profile(stub, symbols)
    profile['id'] = 'pingpong-msxpi-netplay-test'
    data = patcher().gpf_bytes(profile, {'stub': stub})
    Path(gpf_path).write_bytes(data)
    if syms_path:
        write_syms(syms_path, symbols, stub)
    print(f'Test GPF {gpf_path}: {len(data)} bytes, stub {len(stub)} bytes, '
          f'profile hash {struct.unpack_from("<I", data, 8)[0]:08x}')


def publish(assembler, engine, rom, syms):
    stub, symbols = assemble(assembler, engine, False, HERE / 'assets')
    (HERE / 'assets/stub.sym').unlink()
    profile = make_profile(stub, symbols)
    (HERE / 'profile.json').write_text(json.dumps(profile, indent=2) + '\n', encoding='utf-8')
    gpf = patcher().gpf_bytes(profile, {'stub': stub})  # it must compile
    if syms:
        write_syms(syms, symbols, stub)
    print(f'Published profile; stub {len(stub)} of {STUB_MAX} bytes ({STUB_LOAD:04X}h-{symbols["stubEnd"] - 1:04X}h), '
          f'{len(profile["patches"])} patches, GPF {len(gpf)} bytes')
    if rom:
        data = Path(rom).read_bytes()
        check_rom(data, profile)
        print(f'ROM {Path(rom).name}: CRC-32 {zlib.crc32(data):08X}, every expected byte found')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--assembler', required=True, help='sjasmplus executable')
    parser.add_argument('--engine', type=Path, default=ENGINE, help='PLAYNET engine source')
    parser.add_argument('--rom', type=Path, help="the player's PINGPONG.ROM, to check the patches against")
    parser.add_argument('--syms', type=Path, help="also write the release stub's symbols as Tcl, for the rig")
    parser.add_argument('--test-gpf', type=Path, help='write a random-pad test GPF here instead of publishing')
    parser.add_argument('--test-syms', type=Path, help='with --test-gpf: the stub symbols as Tcl (set ::sym(..)), '
                                                       'and the stub itself beside it (.bin)')
    args = parser.parse_args()
    if args.test_gpf:
        test_build(args.assembler, args.engine, args.test_gpf, args.test_syms)
    else:
        publish(args.assembler, args.engine, args.rom, args.syms)
