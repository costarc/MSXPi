#!/usr/bin/env python3
"""Build the Vampire Killer runtime bank and declarative profile from a private original."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

HERE = Path(__file__).resolve().parent
SOURCE_SHA256 = '99eabaaeb2b6c02220e131043d5a6401d0d8c5f413d89204547adcc04d65e7e2'
RUNTIME_BANK = 16          # added 8K bank after the full 128K original
BASE = RUNTIME_BANK * 0x2000
KNOWN = {0x80: 'Stage 1', 0x8a: 'Prologue'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assembler', required=True)
    parser.add_argument('--rom', type=Path, required=True)
    args = parser.parse_args()
    original = args.rom.read_bytes()
    if len(original) != 131072 or hashlib.sha256(original).hexdigest() != SOURCE_SHA256:
        raise ValueError('Expected the analyzed original Vampire Killer revision; refusing another ROM')
    src = HERE/'src'
    assets = HERE/'assets'
    assets.mkdir(exist_ok=True)
    shared = HERE.parent/'goonies/src'
    for name in ('msxpi_bios.asm', 'include.asm', 'payload_generated.asm'):
        (src/name).write_bytes((shared/name).read_bytes())
    runtime = (shared/'runtime.asm').read_text()
    runtime = runtime.replace('org $c000', 'org $8000')
    runtime = runtime.replace('$d000', '$9000').replace('$e000', '$a000')
    # Writable data to RAM (RT_DATA): a store into a Konami window switches
    # banks. The block keeps its initial bytes; boot copies it.
    # Undo the filename escape while copying into the RAM command buffer.
    # Bank 16 is served from msxarch's Konami pair cache, rebuilt from the
    # loaded image whenever the A000h partner changes, so fixing the names up
    # in place at boot was lost ("vampire_02.mp3" reached the Pi as
    # "vampire_0.mp3").
    copy = ('filename_copy:\n        ld a,(hl)\n        ld (de),a\n')
    assert runtime.count(copy) == 1
    runtime = runtime.replace(copy, 'filename_copy:\n        ld a,(hl)\n        cp 2\n'
                              '        jr nz,filename_plain\n        ld a,\'2\'\n'
                              'filename_plain:\n        ld (de),a\n')
    start, end = 'play_prefix:', 'response:     ds 257,0\n'
    assert runtime.count(start) == 1 and runtime.count(end) == 1
    runtime = runtime.replace(start, 'rt_data_image:\n        disp RT_DATA\n' + start)
    runtime = runtime.replace(end, end + 'rt_data_end:\n        ent\n')
    (src/'runtime.asm').write_text('; Generated from Goonies shared runtime by rebuild.py.\n'+runtime)
    subprocess.run([args.assembler, '-DMSXPI_RAM_STASH', '--raw=../assets/runtime.bin',
                    '--sym=runtime.sym', '--lst=runtime.lst', 'runtime.asm'], cwd=src, check=True)
    symbols = {}
    for line in (src/'runtime.sym').read_text().splitlines():
        match = re.match(r'(\w+): EQU 0x([0-9A-Fa-f]+)', line)
        if match:
            symbols[match[1]] = int(match[2], 16)
    data = bytearray((assets/'runtime.bin').read_bytes())
    assert len(data) == 0x2000 and symbols['code_end'] <= 0x9000
    assert symbols['gateway_end'] <= symbols['RT_DATA'] and symbols['rt_data_end'] <= 0xf380
    # In the distributed asset all configuration bytes must be zero.
    data[0x1200:0x1202] = b'\0\0'
    (assets/'runtime.bin').write_bytes(data)
    patches = []

    def patch(offset, expected, replacement, reason):
        if original[offset:offset+len(expected)] != expected or len(expected) != len(replacement):
            raise ValueError(f'Unexpected original at {offset:#x}')
        patches.append(dict(offset=offset, expected=expected.hex(),
                            replace=replacement.hex(), reason=reason))

    # INIT 40B2: DI / H.TIMI := JP 4028h / CLIKSW := 0 / EI / JR $. Now DI /
    # bank 16 at 8000h / JP 8000h; boot copies the gateway to F100h, does the
    # same set-up and idles in the gateway.
    tail = bytes.fromhex('f33ec3329ffd21284022a0fdaf32dbf3fb18fe')
    boot = bytes((0xf3, 0x3e, RUNTIME_BANK, 0x32, 0x00, 0x80, 0xc3, 0x00, 0x80))
    patch(0x00b2, tail, boot + bytes(len(tail) - len(boot)),
          'Start the runtime bank and idle in the RAM gateway, servicing music outside interrupt context')
    patch(0x109f, bytes.fromhex('e5d5c5'), b'\xc3' + struct.pack('<H', symbols['gw_music']),
          'Record music requests at the sound driver entry; the request itself is unchanged')
    ids = range(0x80, 0x90)
    sounds = {f'{i:02x}': {'raw_ids': [i],
                           'description': f'{KNOWN[i]} (music {i:02X}h)' if i in KNOWN else
                           f'Music {i:02X}h; event name not established'}
              for i in ids}
    defaults = dict(tracks={f'vampire_{i:02x}': dict(filename=f'VAMPIRE_{i:02X}.mp3', mode='loop')
                            for i in ids},
                    sounds={f'{i:02x}': f'vampire_{i:02x}' for i in ids},
                    exit_enabled=True, gap_frames=0)
    profile = dict(format='msxpi-rom-patch', version=1, id='vampire-msxpi-konami-v1',
        source=dict(size=len(original), sha256=hashlib.sha256(original).hexdigest()),
        output=dict(size=BASE + 0x2000, fill=0, mapper='Konami'),
        requirements=['MSX2 and MSXPi msxarch writable RAM cartridge loader',
                      'msxarch/msxpi-server that load a ROM ending part-way into a 16 KiB page (17 banks)',
                      'MSXPi music play/loop/stop with decimal playback IDs',
                      'Runtime bank 16 must be writable; direct ROM cartridge loading is unsupported'],
        assets={'runtime': dict(file='assets/runtime.bin', sha256=hashlib.sha256(data).hexdigest())},
        layout=[dict(source='input', offset=0, size=len(original), destination=0),
                dict(source='runtime', offset=0, size=len(data), destination=BASE)],
        patches=patches,
        music=dict(abi='msxpi-music-v1', map_offset=BASE+0x1000, modes_offset=BASE+0x1100,
                   options_offset=BASE+0x1200, names_offset=BASE+0x1210, names_capacity=3568,
                   names_encoding='escape-32'),
        sounds=sounds, defaults=defaults, symbols=symbols)
    (HERE/'profile.json').write_text(json.dumps(profile, indent=2)+'\n', encoding='utf-8')
    (HERE/'music.example.json').write_text(json.dumps(defaults, indent=2)+'\n', encoding='utf-8')
    print('Built Vampire Killer profile with', len(patches), 'guarded changes; code',
          symbols['code_end'] - 0x8000, 'bytes')


if __name__ == '__main__':
    main()
