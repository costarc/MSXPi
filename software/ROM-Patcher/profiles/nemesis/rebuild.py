#!/usr/bin/env python3
"""Build the Nemesis (Gradius) runtime and declarative profile from a private original."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

HERE = Path(__file__).resolve().parent
SOURCE_SHA256 = '3210f8a0f2309dd4b9a89fc2b24d0f178ce4393a0a1f2854fbce545c361261bc'
RUNTIME_BANK = 13          # 8K bank, all FFh in the original
RUNTIME_OFFSET = RUNTIME_BANK * 0x2000
# Melodic sounds: two-channel 16h-25h and three-channel 26h-4Fh (low 7 bits);
# bit 7 is a request flag. Below 16h are single-channel effects on channel 3.
MUSIC_IDS = range(0x16, 0x50)
# Heard in a forced-stage test (stage number poked mid-game), so the stage is
# only indicative. Described, not mapped by default.
HEARD = {0x16: 'heard in stage 2', 0x18: 'heard at start of stage 3',
         0x22: 'heard in stage 5', 0x35: 'heard in stages 3-4',
         0x3b: 'heard between stages 4 and 5'}
KNOWN = {0x26: 'Title', 0x2c: 'Stage 1', 0x42: 'Requested at power-up',
         0x47: 'Player down', 0x4a: 'Game over', 0x4d: 'Game start'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assembler', required=True)
    parser.add_argument('--rom', type=Path, required=True)
    args = parser.parse_args()
    original = args.rom.read_bytes()
    if len(original) != 131072 or hashlib.sha256(original).hexdigest() != SOURCE_SHA256:
        raise ValueError('Expected the analyzed original Nemesis revision; refusing another ROM')
    if original[RUNTIME_OFFSET:RUNTIME_OFFSET+0x2000] != b'\xff' * 0x2000:
        raise ValueError('Runtime bank is not free in this ROM')
    src = HERE/'src'
    assets = HERE/'assets'
    assets.mkdir(exist_ok=True)
    shared = HERE.parent/'goonies/src'
    for name in ('msxpi_bios.asm', 'include.asm', 'payload_generated.asm', 'runtime.asm'):
        (src/name).write_bytes((shared/name).read_bytes())
    subprocess.run([args.assembler, '-DMSXPI_RAM_STASH', '--raw=../assets/runtime.bin',
                    '--sym=runtime.sym', '--lst=runtime.lst', 'runtime.asm'], cwd=src, check=True)
    symbols = {}
    for line in (src/'runtime.sym').read_text().splitlines():
        match = re.match(r'(\w+): EQU 0x([0-9A-Fa-f]+)', line)
        if match:
            symbols[match[1]] = int(match[2], 16)
    data = bytearray((assets/'runtime.bin').read_bytes())
    assert len(data) == 0x2000 and symbols['code_end'] <= 0xd000
    assert symbols['resident_boot'] == 0xc000
    # In the distributed asset all configuration bytes must be zero.
    data[0x1200:0x1202] = b'\0\0'
    (assets/'runtime.bin').write_bytes(data)
    patches = []

    def patch(offset, expected, replacement, reason):
        if original[offset:offset+len(expected)] != expected or len(expected) != len(replacement):
            raise ValueError(f'Unexpected original at {offset:#x}')
        patches.append(dict(offset=offset, expected=expected.hex(),
                            replace=replacement.hex(), reason=reason))

    def jp(symbol):
        return b'\xc3' + struct.pack('<H', symbols[symbol])

    # INIT 4095: LD A,C3h / LD (FD9Ah),A / LD HL,4028h / LD (FD9Bh),HL, the
    # H.KEYI hook install, just after ENASLT put the cartridge in page 2. Now
    # DI / bank 13 at 8000h / JP 8000h; resident_boot copies itself to C000h,
    # installs the hook and returns to 40A0h.
    hook = bytes.fromhex('3ec332 9afd 212840 229bfd'.replace(' ', ''))
    boot = bytes((0xf3, 0x3e, RUNTIME_BANK, 0x32, 0x00, 0x80, 0xc3, 0x00, 0x80))
    patch(0x0095, hook, boot + bytes(len(hook) - len(boot)),
          'Load runtime bank 13 into page 3 RAM before the game hook starts')
    patch(0x00de, bytes.fromhex('fb18fe'), jp('idle'),
          'Idle in the runtime, servicing music outside interrupt context')
    patch(0xe222, bytes.fromhex('790fc688'), jp('volume_hook') + b'\0',
          'Silence mapped music channels only after successful external playback')
    sounds = {f'{i:02x}': {'raw_ids': [i, 0x80 + i],
                           'description': (KNOWN.get(i) or HEARD.get(i, 'event name not established'))
                                          + f' ({"two" if i < 0x26 else "three"}-channel sound {i:02X}h)'}
              for i in MUSIC_IDS}
    defaults = dict(tracks={f'nemesis_{i:02x}': dict(filename=f'NEMESIS_{i:02X}.mp3', mode='loop')
                            for i in KNOWN},
                    sounds={f'{i:02x}': (f'nemesis_{i:02x}' if i in KNOWN else None) for i in MUSIC_IDS},
                    exit_enabled=True, gap_frames=30)
    base = RUNTIME_OFFSET
    profile = dict(format='msxpi-rom-patch', version=1, id='nemesis-msxpi-konami-v1',
        source=dict(size=len(original), sha256=hashlib.sha256(original).hexdigest()),
        output=dict(size=len(original), fill=0, mapper='Konami'),
        requirements=['MSXPi msxarch writable RAM cartridge loader',
                      'At least 16 KiB page-3 RAM (runtime at C000-DFFF)',
                      'MSXPi music play/loop/stop with decimal playback IDs',
                      'Exit requires msxarch RAM loading; clear server ROM cache after replacing a named ROM'],
        assets={'runtime': dict(file='assets/runtime.bin', sha256=hashlib.sha256(data).hexdigest())},
        layout=[dict(source='input', offset=0, size=base, destination=0),
                dict(source='runtime', offset=0, size=len(data), destination=base),
                dict(source='input', offset=base+0x2000, size=len(original)-base-0x2000,
                     destination=base+0x2000)],
        patches=patches,
        music=dict(abi='msxpi-music-v1', map_offset=base+0x1000, modes_offset=base+0x1100,
                   options_offset=base+0x1200, names_offset=base+0x1210, names_capacity=3568,
                   names_encoding='escape-32'),
        sounds=sounds, defaults=defaults, symbols=symbols)
    (HERE/'profile.json').write_text(json.dumps(profile, indent=2)+'\n', encoding='utf-8')
    (HERE/'music.example.json').write_text(json.dumps(defaults, indent=2)+'\n', encoding='utf-8')
    print('Built Nemesis profile with', len(patches), 'guarded changes; code',
          symbols['code_end'] - 0xc000, 'bytes')


if __name__ == '__main__':
    main()
