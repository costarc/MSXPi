"""Regression: PCHESS / PCHECKERS on an MSX with NO MSXPi interface.

With no interface port $56 floats to $FF and CHKPIRDY() waited on it for ever,
so the first MSXPi exchange (a move key, or opening the ESC menu) froze the
MSX. The emulated MSX (Canon V-25 + 2 MB mapper + Panasonic FS-FD1A disk, no
-ext MSXPi) must now:

  1. show NO MSXPI on the status line when a key needs the server (no freeze),
  2. open the ESC menu at once,
  3. reach LINK: TCPIP (no INL loaded: NO TCP/IP UNAPI - RUN INL I),
  4. EXIT to the DOS prompt.

    python pchess_nopi_openmsx.py [pchess|pcheckers]
The MSX-DOS 1 disk is msxpiboot.dsk with the program added. Artefacts go to
<repo>/../work/<game>-nopi-*/ (the same place as the other openMSX tests).
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[1]
sys.path.insert(0, str(HERE))
from pchess_tcpip_openmsx import screen_report, text_at, write_script  # noqa: E402,F401
import pchess_tcpip_openmsx as base  # noqa: E402

OPENMSX = os.environ.get('OPENMSX', base.OPENMSX)
GAME = (sys.argv[1] if len(sys.argv) > 1 else 'pchess').lower()
PROGRAM = Path(os.environ.get('GAME_COM', SOFTWARE / f'target/{GAME}.com'))
EXIT_ROW = {'pchess': 8, 'pcheckers': 9}[GAME]
ESC, DOWN, RIGHT = base.ESC, base.DOWN, base.RIGHT
MENU_X, MENU_Y = 44, 72

TIMELINE = [
    (20, GAME.upper() + '\r'), (32, 'dump:start'),
    # PChess: key 1 asks the server. PCheckers: 1 is local, a ROOM needs it.
    (34, '1' if GAME == 'pchess' else '4'), (35, 'x\r'), (38, 'dump:key1'),
    (40, ESC), (44, 'dump:menu'),
    (46, DOWN + DOWN + RIGHT + '\r'), (50, 'dump:link'),
    (52, ESC), (54, DOWN * EXIT_ROW + '\r'), (60, 'dump:dos'), (62, 'quit'),
]


def main():
    (SOFTWARE.parent / 'work').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=f'{GAME}-nopi-', dir=SOFTWARE.parent / 'work'))
    dumps = work / 'vram'
    dumps.mkdir()
    disk = work / 'boot.dsk'
    shutil.copy(SOFTWARE / 'target/disks/msxpiboot.dsk', disk)
    shutil.copy(PROGRAM, work / f'{GAME}.com')
    subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', f'{GAME}.com',
                    f'boot.dsk:{GAME.upper()}.COM'], cwd=work, check=True, stdout=subprocess.DEVNULL)

    base.TIMELINE[:] = TIMELINE
    script = work / 'run.tcl'
    write_script(script, dumps)
    with script.open('a') as f:
        f.write(f'diska {(work / "boot.dsk").as_posix()}\n')
    # diska must run before the machine boots: put it first.
    lines = script.read_text().splitlines()
    # The MSXPi server port setting does not exist without the extension.
    script.write_text('\n'.join([l for l in lines if l.startswith('diska')] +
                                [l for l in lines if not l.startswith(('diska', 'set msxpiserver_port'))]) + '\n')

    with (work / 'openmsx.log').open('w') as out:
        subprocess.run([OPENMSX, '-machine', 'Canon_V-25', '-ext', 'ram2mb', '-ext', 'Panasonic_FS-FD1A',
                        '-command', 'set renderer none', '-script', str(script)],
                       stdout=out, stderr=subprocess.STDOUT, timeout=300)

    screens, raw = {}, {}
    for name in ('start', 'key1', 'menu', 'link', 'dos'):
        path = dumps / f'{name}.vram'
        if path.exists():
            raw[name] = path.read_bytes()
            screens[name] = screen_report(raw[name])
            print(f'[{name}]', screens[name])

    failures = []

    def check(name, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + name + (' - ' + str(detail) if detail and not ok else ''))
        if not ok:
            failures.append(name)

    s = screens.get
    check('key1: no freeze, NO MSXPI status', s('key1') and s('key1')['status'] == 'NO MSXPI - ESC MENU LINK TCPIP',
          s('key1'))
    menu = raw.get('menu')
    check('menu opens (M E N U)', menu and text_at(menu, MENU_X + 40, MENU_Y + 5, 7) == 'M E N U',
          menu and text_at(menu, MENU_X + 40, MENU_Y + 5, 7))
    check('menu row LINK: MSXPI', menu and text_at(menu, MENU_X + 8, MENU_Y + 16 + 2 * 9, 20) == '  LINK: MSXPI',
          menu and text_at(menu, MENU_X + 8, MENU_Y + 16 + 2 * 9, 20))
    check('TCPIP reachable without INL', s('link') and s('link')['status'] == 'NO TCP/IP UNAPI - RUN INL I',
          s('link'))
    check('exit to DOS prompt', raw.get('dos') and b'A:' in raw['dos'][:960], 'no A: prompt in the text screen')
    print('artefacts in', work)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
