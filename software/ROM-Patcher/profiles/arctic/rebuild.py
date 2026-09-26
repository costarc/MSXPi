#!/usr/bin/env python3
"""Build Arctic's banked runtime and declarative profile from a private original."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
SOURCE_SHA256 = '3dcb85704006e2a3d95f11e9e2dbf13f1457b55f89727d70940ed7720ea0c78c'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assembler', required=True)
    parser.add_argument('--rom', type=Path, required=True)
    args = parser.parse_args()
    original = args.rom.read_bytes()
    if len(original) != 131072 or hashlib.sha256(original).hexdigest() != SOURCE_SHA256:
        raise ValueError('Expected the analyzed original Arctic revision; refusing another ROM')
    src = HERE/'src'
    assets = HERE/'assets'
    assets.mkdir(exist_ok=True)
    shared = HERE.parent/'goonies/src'
    for name in ('msxpi_bios.asm', 'include.asm', 'payload_generated.asm'):
        (src/name).write_bytes((shared/name).read_bytes())
    runtime = (shared/'runtime.asm').read_text()
    runtime = runtime.replace('org $c000', 'org $8000')
    runtime = runtime.replace('$d000', '$9000').replace('$e000', '$a000')
    (src/'runtime.asm').write_text('; Generated from Goonies shared runtime by rebuild.py.\n'+runtime)
    symbols = {}
    for name in ('runtime', 'gateway'):
        subprocess.run([args.assembler, '-DMSXPI_RAM_STASH',
                        f'--raw=../assets/{name}.bin', f'--sym={name}.sym',
                        f'{name}.asm'], cwd=src, check=True)
        for line in (src/f'{name}.sym').read_text().splitlines():
            match = re.match(r'(\w+): EQU 0x([0-9A-Fa-f]+)', line)
            if match:
                symbols[match[1]] = int(match[2], 16)
    data = bytearray((assets/'runtime.bin').read_bytes())
    data[0x1200:0x1202] = b'\0\0'
    (assets/'runtime.bin').write_bytes(data)
    patches = []

    def patch(offset, expected, replacement, reason):
        if original[offset:offset+len(expected)] != expected:
            raise ValueError(f'Unexpected original at {offset:#x}')
        patches.append(dict(offset=offset, expected=expected.hex(),
                            replace=replacement.hex(), reason=reason))

    def call(symbol):
        return b'\xcd' + symbols[symbol].to_bytes(2, 'little')

    gateway = (assets/'gateway.bin').read_bytes()
    patch(0x3e80, bytes(len(gateway)), gateway, 'Fixed-bank gateway and private state')
    for addr in (0x4045, 0x4099, 0x40e1):
        patch(addr-0x4000, bytes.fromhex('320070'), call('bank_select'),
              'Record page-2 bank, including copied F080 helper')
    patch(0x3748, bytes.fromhex('f53eff'), b'\xc3'+symbols['music_event'].to_bytes(2,'little'),
          'Capture music ID; retain original sequencer and native fallback')
    patch(0x3e6d, bytes.fromhex('cd9300'), call('music_volume'),
          'Mute only melodic volume when external playback is active')
    # Decoded foreground code regions only. Exclude the timer handler and
    # its keyboard/joystick helper; wire exchanges must never run in an ISR.
    for start, end in ((0x0000, 0x0a4e), (0x0aff, 0x1856), (0x400c, 0x5a00), (0x6450, 0x6600)):
        for offset in range(start, end-2):
            for lo, label in ((0x54, 'poll54'), (0x55, 'poll55')):
                expected = bytes((0x3a, lo, 0xc0))
                if original[offset:offset+3] == expected:
                    patch(offset, expected, call(label), 'Service music/exit once per frame at foreground input poll')
    sounds = {f'{i:02x}': {'raw_ids': [i], 'description': f'Arctic music selector {i}; event name not established'}
              for i in range(1, 15)}
    defaults = dict(tracks={f'track_{i:02d}': dict(filename=f'ARCTIC_{i:02d}.mp3', mode='loop')
                            for i in range(1, 15)},
                    sounds={f'{i:02x}': f'track_{i:02d}' for i in range(1, 15)},
                    exit_enabled=True, gap_frames=0)
    profile = dict(format='msxpi-rom-patch', version=1, id='arctic-msxpi-ascii16-v1',
        source=dict(size=len(original), sha256=hashlib.sha256(original).hexdigest()),
        output=dict(size=0x22000, fill=0, mapper='ASCII16'),
        requirements=['MSX2 and MSXPi msxarch writable RAM cartridge loader',
                      'Enough mapper RAM for 144 KiB (nine banks) and loader',
                      'MSXPi music play/loop/stop with decimal playback IDs',
                      'Runtime bank 8 must be writable; direct ROM cartridge loading is unsupported'],
        assets={'runtime': dict(file='assets/runtime.bin', sha256=hashlib.sha256(data).hexdigest())},
        layout=[dict(source='input', offset=0, size=len(original), destination=0),
                dict(source='runtime', offset=0, size=len(data), destination=0x20000)],
        patches=patches,
        music=dict(abi='msxpi-music-v1', map_offset=0x21000, modes_offset=0x21100,
                   options_offset=0x21200, names_offset=0x21210, names_capacity=3568, names_encoding='escape-32'),
        sounds=sounds, defaults=defaults, symbols=symbols)
    (HERE/'profile.json').write_text(json.dumps(profile, indent=2)+'\n')
    (HERE/'music.example.json').write_text(json.dumps(defaults, indent=2)+'\n')
    print('Built Arctic profile with', len(patches), 'guarded changes')


if __name__ == '__main__':
    main()
