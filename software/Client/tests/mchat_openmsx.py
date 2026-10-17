"""End-to-end: MCHAT.COM (MSX1, SCREEN 2) in openMSX through a real MSXPi server.

The emulated MSX (Canon V-25 + MSXPi, MSX-DOS 1 from msxpiboot.dsk) starts
"MCHAT alice". The IRC server is pchess_irc_fixture on this host (the MSXPi
server is pointed at it with PCHESS_IRC_* variables) and "bob" is a plain
socket in the fixture. Bob talks in #msxpi and sends alice a private line;
alice answers, joins a second room, switches rooms and scrolls back. The
screen is read back from VRAM: SCREEN 2 text is decoded with the same 4x8
font the program draws with (tools/gen_mchat_font.py).

    python mchat_openmsx.py [path\\to\\mchat.com]

Windows Python and openMSX with the MSXPi extension. Ports 5044 and 6668
must be free. Artefacts go to <repo>/../work/mchat-*/.
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[1]
sys.path.insert(0, str(SOFTWARE / 'Server/Python/tests'))
sys.path.insert(0, str(SOFTWARE / 'Client/tools'))
from pchess_irc_fixture import Server  # noqa: E402
import gen_mchat_font  # noqa: E402

OPENMSX = os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe')
MCHAT = Path(sys.argv[1] if len(sys.argv) > 1 else os.environ.get('MCHAT_COM', SOFTWARE / 'target/mchat.com'))
MSXPI_PORT = int(os.environ.get('MSXPI_TEST_PORT', '5044'))
IRC_PORT = int(os.environ.get('MCHAT_IRC_PORT', '6668'))

UP, DOWN, TAB, ESC = chr(30), chr(31), chr(9), chr(27)
TIMELINE = [
    (15, 'shot:boot'), (22, 'mchat alice\r'), (30, 'shot:early'), (40, 'dump:start'), (41, 'shot:start'),
    (42, 'hello bob\r'), (50, '/join #second\r'), (60, 'dump:second'),
    (62, 'only here\r'), (68, TAB), (76, 'dump:back'),
    (78, UP + UP), (86, 'dump:scrolled'),
    (90, ESC), (100, 'quit'),
]

GLYPH_ROWS = {}
for _i, _g in enumerate(gen_mchat_font.GLYPHS):
    GLYPH_ROWS[tuple(int(r, 16) for r in _g)] = chr(32 + _i)


def pattern_bit(vram, x, y):
    return vram[((y // 8) * 32 + x // 8) * 8 + y % 8] >> (7 - x % 8) & 1


def screen_text(vram):
    """The 24 rows of 51 characters, decoded from the pattern table."""
    lines = []
    for r in range(24):
        line = ''
        for c in range(51):
            rows = []
            for y in range(8):
                rows.append(sum(pattern_bit(vram, c * 5 + x, r * 8 + y) << (3 - x) for x in range(4)))
            line += GLYPH_ROWS.get(tuple(rows), '?')
        lines.append(line)
    return lines


def tcl_string(text):
    return ''.join(c if c.isalnum() or c in ' ' else '\\x%02x' % ord(c) for c in text)


def write_script(path, dumps):
    lines = ['set save_settings_on_exit off', f'set msxpiserver_port {MSXPI_PORT}',
             'set speed 100', 'set power on',
             'proc dump {name} {',
             f'    set f [open "{dumps.as_posix()}/$name.vram" w]',
             '    fconfigure $f -translation binary',
             '    puts -nonewline $f [debug read_block VRAM 0 16384]',
             '    close $f', '}']
    for when, action in TIMELINE:
        if action == 'quit':
            lines.append(f'after time {when} {{exit}}')
        elif action.startswith('dump:'):
            lines.append(f'after time {when} {{dump {action[5:]}}}')
        elif action.startswith('shot:'):
            lines.append(f'after time {when} {{screenshot "{dumps.as_posix()}/{action[5:]}.png"}}')
        else:
            lines.append(f'after time {when} {{type_via_keybuf "{tcl_string(action)}"}}')
    path.write_text('\n'.join(lines) + '\n')


class Bob(threading.Thread):
    """A second IRC user in the fixture."""

    def __init__(self, fixture):
        super().__init__(daemon=True)
        self.fixture = fixture
        self.sock = socket.create_connection(('127.0.0.1', IRC_PORT))
        self.done = False

    def send(self, line):
        self.sock.sendall((line + '\r\n').encode())

    def run(self):
        self.send('NICK bob')
        self.send('USER bob 0 * :bob')
        self.send('JOIN #msxpi')
        end = time.time() + 120
        while time.time() < end and 'alice' not in self.fixture.clients:
            time.sleep(.1)
        time.sleep(4)
        self.send('PRIVMSG #msxpi :hello everyone')
        time.sleep(.5)
        self.send('PRIVMSG alice :psst alice')
        # The filler comes once alice has spoken, so the first screen shows the rest.
        while time.time() < end and not any(m == 'hello bob' for _, _, m in self.fixture.transcript):
            time.sleep(.1)
        time.sleep(2)
        for i in range(1, 31):
            self.send(f'PRIVMSG #msxpi :filler line {i}')
            time.sleep(.05)
        while not self.done:
            time.sleep(.2)


def main():
    (SOFTWARE.parent / 'work').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='mchat-', dir=SOFTWARE.parent / 'work'))
    home, dumps = work / 'home', work / 'vram'
    (home / 'disks').mkdir(parents=True)
    dumps.mkdir()
    shutil.copy(SOFTWARE / 'target/disks/msxpiboot.dsk', home / 'disks/msxpiboot.dsk')
    shutil.copy(SOFTWARE / 'target/disks/tools.dsk', home / 'disks/tools.dsk')
    shutil.copy(MCHAT, work / 'mchat.com')
    subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'mchat.com',
                    'home/disks/msxpiboot.dsk:MCHAT.COM'], cwd=work, check=True, stdout=subprocess.DEVNULL)
    script = work / 'mchat.tcl'
    write_script(script, dumps)

    fixture = Server(('127.0.0.1', IRC_PORT))
    threading.Thread(target=fixture.serve_forever, daemon=True).start()
    bob = Bob(fixture)
    env = dict(os.environ, MSXPI_HOME=str(home), MSXPI_PORT=str(MSXPI_PORT), PCHESS_IRC_HOST='127.0.0.1',
               PCHESS_IRC_PORT=str(IRC_PORT), PCHESS_IRC_TLS='0')
    server_log = (work / 'server.log').open('w')
    server = subprocess.Popen([sys.executable, '-u', 'msxpi-server.py'], env=env,
                              cwd=SOFTWARE / 'Server/Python/src', stdout=server_log, stderr=subprocess.STDOUT)
    failures = []

    def check(ok, message):
        print(('PASS: ' if ok else 'FAIL: ') + message, flush=True)
        if not ok:
            failures.append(message)

    try:
        time.sleep(3)
        bob.start()
        with (work / 'openmsx.log').open('w') as out:
            subprocess.run([OPENMSX, '-machine', 'Canon_V-25', '-ext', 'ram2mb', '-ext', 'MSXPi',
                            '-command', 'set renderer none' if not os.environ.get('MCHAT_SHOW') else 'set speed 100', '-script', str(script)],
                           stdout=out, stderr=subprocess.STDOUT, timeout=600)
    finally:
        bob.done = True
        server.terminate()
        server.wait()
        server_log.close()

    screens = {}
    for name in ('start', 'second', 'back', 'scrolled'):
        path = dumps / f'{name}.vram'
        if path.exists():
            screens[name] = screen_text(path.read_bytes())
            print(f'[{name}]')
            print('\n'.join(line.rstrip() for line in screens[name]), flush=True)
    start = '\n'.join(screens.get('start', []))
    check('#MSXPI' in start.upper() or '#msxpi' in start, 'room tab is shown')
    check('bob: hello everyone' in start, 'bob\'s public line is shown')
    check('*bob* psst alice' in start, 'private line is shown')
    check('USERS' in start and 'bob' in start.split('\n')[2] + start.split('\n')[3], 'user list shows bob')
    check(any(m == 'hello bob' for _, t, m in fixture.transcript), 'alice\'s line reached the IRC server')
    second = '\n'.join(screens.get('second', []))
    check('#second' in second, 'second room tab appears')
    check(('alice', '#second', 'only here') in fixture.transcript, 'line went to the second room')
    back = '\n'.join(screens.get('back', []))
    check('#msxpi' in back and 'filler line 30' in back, 'TAB returns to #msxpi at the latest line')
    scrolled = '\n'.join(screens.get('scrolled', []))
    check('SCROLLED' in scrolled and 'filler line 30' not in scrolled, 'UP scrolls back through history')
    print('Test artifacts:', work, flush=True)
    fixture.shutdown()
    fixture.server_close()
    if failures:
        sys.exit(1)


if __name__ == '__main__':
    main()
