"""Smoke test: PPOKER.COM on an MSX with no MSXPi interface.

Boots msxpiboot.dsk with PPOKER.COM added on an emulated Canon V-25 (MSX2,
SCREEN 5), types PPOKER, opens the join prompt, presses ESC and then walks the
menu to EXIT TO DOS.  Nothing is asserted: every frame is saved as a PNG with
the game's palette so the screens can be looked at, in
work/poker-smoke-*/vram/*.png.

Keys are sent on wall-clock time, so on a loaded machine some of them land
before MSX-DOS has run the program.  Read the frames to see what arrived.

    python poker_smoke_openmsx.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[1]
OPENMSX = os.environ.get(
    'OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.7.0/openmsx.exe')
ESC, DOWN = '\x1b', '\x1b[B'

# The palette of ppoker.c, 3 bits per component, as V9938 SCREEN 5 stores it.
PALETTE = [(0, 0, 0), (1, 0, 0), (0, 4, 1), (1, 6, 2), (5, 0, 0), (7, 1, 1),
           (3, 2, 0), (7, 4, 0), (2, 2, 2), (7, 2, 2), (6, 6, 0), (7, 7, 1),
           (0, 0, 3), (1, 1, 6), (4, 4, 4), (7, 7, 7)]

# The emulator lags wall time, so keys come late and frames are dumped
# regularly: every frame is rendered and kept.
TIMELINE = ([(24, 'PPOKER\r'), (46, 'j'), (49, 't1\r'), (74, ESC),
             (86, DOWN * 5 + '\r')] +
            [(at, 'dump:s%02d' % at) for at in range(30, 96, 4)] +
            [(98, 'quit')])


def tcl_string(text):
    return text.replace('\\', '\\\\').replace('"', '\\"').replace('\r', '\\r')


def write_script(path, dumps, disk):
    lines = ['set save_settings_on_exit off', 'set speed 100', 'set power on',
             f'diska "{(disk).as_posix()}"',
             'proc dump {name} {',
             f'    set f [open "{dumps.as_posix()}/$name.vram" w]',
             '    fconfigure $f -translation binary',
             '    puts -nonewline $f [debug read_block VRAM 0 32768]',
             '    close $f', '}']
    for when, action in TIMELINE:
        if action == 'quit':
            lines.append(f'after time {when} {{dump final; exit}}')
        elif action.startswith('dump:'):
            lines.append(f'after time {when} {{dump {action[5:]}}}')
        else:
            lines.append(f'after time {when} {{type_via_keybuf "{tcl_string(action)}"}}')
    path.write_text('\n'.join(lines) + '\n')


def render(vram, path, scale=2):
    """SCREEN 5 page 0 to a PNG, four pixels a byte, palette from ppoker.c."""
    from PIL import Image
    image = Image.new('RGB', (256, 212))
    pixels = image.load()
    for y in range(212):
        row = vram[y * 128:(y + 1) * 128]
        for x in range(256):
            value = (row[x // 2] >> 4) if x % 2 == 0 else (row[x // 2] & 15)
            r, g, b = PALETTE[value]
            pixels[x, y] = (r * 255 // 7, g * 255 // 7, b * 255 // 7)
    image.resize((256 * scale, 212 * scale), Image.NEAREST).save(path)


def main():
    (SOFTWARE.parent / 'work').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='poker-smoke-', dir=SOFTWARE.parent / 'work'))
    dumps = work / 'vram'
    dumps.mkdir()
    disk = work / 'boot.dsk'
    shutil.copy(SOFTWARE / 'target/disks/msxpiboot.dsk', disk)
    shutil.copy(SOFTWARE / 'target/ppoker.com', work / 'ppoker.com')
    subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'ppoker.com',
                    'boot.dsk:PPOKER.COM'], cwd=work, check=True, stdout=subprocess.DEVNULL)
    script = work / 'run.tcl'
    write_script(script, dumps, disk.resolve())
    with (work / 'openmsx.log').open('w') as out:
        subprocess.run([OPENMSX, '-machine', 'Canon_V-25', '-ext', 'ram2mb',
                        '-ext', 'Panasonic_FS-FD1A', '-command', 'set renderer none',
                        '-script', str(script)],
                       stdout=out, stderr=subprocess.STDOUT, timeout=300)
    for dump in sorted(dumps.glob('*.vram')):
        render(dump.read_bytes(), dump.with_suffix('.png'))
    print('screens in', work)
    return 0


if __name__ == '__main__':
    sys.exit(main())
