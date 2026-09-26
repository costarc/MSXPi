#!/usr/bin/env python3
"""Developer-only: assemble payload and publish the declarative Goonies profile."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

HERE = Path(__file__).resolve().parent


def rebuild(assembler):
    subprocess.run([assembler, '-DMSXPI_RAM_STASH', '--raw=../assets/resident.bin',
                    '--sym=resident.sym', '--lst=resident.lst', 'runtime.asm'], cwd=HERE/'src', check=True)
    symbols = {}
    for line in (HERE/'src/resident.sym').read_text().splitlines():
        match = re.match(r'(\w+): EQU 0x([0-9A-Fa-f]+)', line)
        if match:
            symbols[match[1]] = int(match[2], 16)
    resident = (HERE/'assets/resident.bin').read_bytes()
    assert len(resident) == 8192 and symbols['code_end'] <= 0xd000
    patches = []

    def patch(offset, expected, replacement, reason):
        patches.append({'offset': offset, 'expected': expected.hex(),
                        'replace': replacement.hex(), 'reason': reason})

    def jp(symbol):
        return b'\xc3' + struct.pack('<H', symbols[symbol])

    patch(0, b'\0'*4, b'AB\x10\x40', 'ASCII16 bootstrap cartridge header')
    boot = b'\xf3\x21\x00\x41\x11\x00\xc0\x01\x00\x20\xed\xb0' + jp('resident_boot')
    patch(0x10, b'\0'*len(boot), boot, 'Copy 8 KiB runtime/configuration to page 3 RAM')
    for offset, expected in [(0x8022, '221c41'), (0x8050, '222941'), (0x80ba, 'cbb6')]:
        before = bytes.fromhex(expected)
        patch(offset, before, b'\0'*len(before), 'Neutralize original mirrored-ROM write in RAM')
    patch(0x80b4, bytes.fromhex('fb18fe'), jp('idle'), 'Service music outside interrupt context')
    patch(0x776c, bytes.fromhex('790fc688'), jp('volume_hook')+b'\0',
          'Filter mapped music channel volumes only after successful external playback')
    sounds = {f'{i:02x}': {'raw_ids': [0x80+i, 0xc0+i],
                         'description': f'Normalized melodic sound ID 0x{i:02X}; descriptive name not yet identified'}
              for i in range(0x0f, 0x2d)}
    defaults = {'tracks': {'default': {'filename': 'The_Goonies_R_Good_Enough.mp3', 'mode': 'loop'}},
                'sounds': {key: 'default' for key in sounds}, 'exit_enabled': True, 'gap_frames': 120}
    # In the distributed asset all configuration bytes must be zero.
    # The assembly defaults document their runtime meaning; patcher owns values.
    resident = bytearray(resident)
    resident[0x1200:0x1202] = b'\0\0'
    (HERE/'assets/resident.bin').write_bytes(resident)
    profile = {
        'format': 'msxpi-rom-patch', 'version': 1, 'id': 'goonies-msxpi-ascii16-v1',
        'source': {'size': 32768, 'sha256': '2ba602b1a17e4797da1588afe6e65640331c15746bf5959f4778b404be929dde'},
        'output': {'size': 65536, 'fill': 0, 'mapper': 'ASCII16'},
        'requirements': ['MSXPi music play/loop/stop commands with decimal playback IDs',
                         'Corrected msxarch RAM mapper loader (state at F900, handlers FAC0/FAD8)',
                         'At least 16 KiB page-3 RAM; validated setup Canon V-25 + MSXPi + ram4mb',
                         'Exit requires msxarch RAM loading; clear server ROM cache after replacing a named ROM'],
        'assets': {'resident': {'file': 'assets/resident.bin', 'sha256': hashlib.sha256(resident).hexdigest()}},
        'layout': [{'source': 'resident', 'offset': 0, 'size': len(resident), 'destination': 0x100},
                   {'source': 'input', 'offset': 0x4000, 'size': 0x4000, 'destination': 0x4000},
                   {'source': 'input', 'offset': 0, 'size': 0x4000, 'destination': 0x8000}],
        'patches': patches,
        'music': {'abi': 'msxpi-music-v1', 'map_offset': 0x1100, 'modes_offset': 0x1200,
                  'options_offset': 0x1300, 'names_offset': 0x1310, 'names_capacity': 3568,
                  'names_encoding': 'escape-32'},
        'sounds': sounds, 'defaults': defaults, 'symbols': symbols}
    (HERE/'profile.json').write_text(json.dumps(profile, indent=2)+'\n', encoding='utf-8')
    (HERE/'music.example.json').write_text(json.dumps(defaults, indent=2)+'\n', encoding='utf-8')
    print(f'Published profile; code={symbols["code_end"]-0xc000} bytes, resident={len(resident)} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assembler', required=True, help='sjasmplus executable')
    rebuild(parser.parse_args().assembler)
