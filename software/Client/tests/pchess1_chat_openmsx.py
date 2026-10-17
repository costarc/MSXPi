"""End-to-end chat for pchess1 (MSX1): two openMSX National CF-3300 (MSX1, TMS9929A; A: is the MSXPi disk) + two MSXPi
servers + the IRC fixture. Same script as pchess_chat_openmsx.py (alice and bob
match through the lobby and talk), but the screens are read from the SCREEN 2
name table: characters 128-223 are the white font, 32-126 the yellow one the
chat window loads for private rows.

    python pchess1_chat_openmsx.py [path\\to\\pchess1.com]

Windows Python with python-chess, openMSX with the MSXPi extension. Ports
5041, 5042 and 5081 must be free.
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
from pchess_irc_fixture import Server  # noqa: E402

OPENMSX = Path(os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe'))
PCHESS = Path(sys.argv[1] if len(sys.argv) > 1 else SOFTWARE / 'target/pchess1.com')
PORTS = (5041, 5042, 5081)
NICKS = ('alice', 'bob')
NAMTBL, CHAT_TOP, CHAT_ROWS = 0x1800, 1, 21
TAB = '\\t'
BOOT_EXTRA = 8   # the DOS date prompt and loading pchess1 take longer than on the MSX2
KEYS = (
    [(38, '4'), (44, TAB), (46, 'anyone here\\r'), (49, '\\x1b'), (51, '5'), (55, '6'),
     (57, 'bob\\r'), (68, TAB), (70, 'hello bob\\r'), (94, 'dump:chat'),
     (98, '\\x1b'), (100, TAB), (104, 'dump:reopened'), (106, '\\x1b'), (110, 'dump:closed'), (112, 'quit')],
    [(38, '4'), (64, '7'), (78, 'dump:unread'), (82, TAB), (86, 'hi alice!\\r'), (94, 'dump:chat'),
     (98, '\\x1b'), (100, TAB), (104, 'dump:reopened'), (106, '\\x1b'), (110, 'dump:closed'), (112, 'quit')],
)


def tcl_script(index, work):
    lines = ['set save_settings_on_exit off', f'set msxpiserver_port {PORTS[index]}',
             'set speed 100', 'set power on', 'set pause off',
             'proc dump {name} {',
             f'    set f [open "{work.as_posix()}/client-{index}-$name.vram" w]',
             '    fconfigure $f -translation binary',
             '    puts -nonewline $f [debug read_block VRAM 0 16384]',
             '    close $f', '}',
             'after time 30 {type_via_keybuf "\\r"}',
             'after time 34 {type_via_keybuf "pchess1\\r"}']
    for when, action in KEYS[index]:
        when += BOOT_EXTRA
        if action.startswith('dump:'):
            lines.append(f'after time {when} {{dump {action[5:]}}}')
        elif action == 'quit':
            lines.append(f'after time {when} {{exit}}')
        else:
            lines.append(f'after time {when} {{type_via_keybuf "{action}"}}')
    return '\n'.join(lines) + '\n'


def row(vram, r, col=0, count=32):
    """(text, colour) of a name-table row; colour is 'white', 'yellow' or 'mixed'."""
    text, kinds = '', set()
    for c in vram[NAMTBL + r * 32 + col:NAMTBL + r * 32 + col + count]:
        if c >= 128:
            text += chr(c - 96)
            kinds.add('white')
        elif 32 <= c < 127:
            text += chr(c)
            kinds.add('yellow')
        else:
            text += '?'
    text = text.strip()
    kinds = kinds if text else set()
    return text, ('mixed' if len(kinds) > 1 else kinds.pop() if kinds else '')


def chat_lines(vram):
    """[(text, 'public'|'private')] for non-blank rows. A blank cell is char
    128 (white) or 32 (yellow); the colour comes from the visible glyphs."""
    out = []
    for r in range(CHAT_TOP, CHAT_TOP + CHAT_ROWS):
        cells = vram[NAMTBL + r * 32:NAMTBL + r * 32 + 32]
        text = ''.join(chr(c - 96) if c >= 128 else chr(c) if 32 <= c < 127 else '?' for c in cells).rstrip()
        if text:
            visible = [c for c in cells if c not in (32, 128)]
            white = any(c >= 128 for c in visible)
            yellow = any(c < 128 for c in visible)
            out.append((text, 'mixed' if white and yellow else 'private' if yellow else 'public'))
    return out


def main():
    for port in PORTS:
        with socket.socket() as probe:
            if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            probe.bind(('127.0.0.1', port))
    work = Path(tempfile.mkdtemp(prefix='pchess1-chat-'))
    for i in range(2):
        (work / f'home{i}/disks').mkdir(parents=True)
        for name in ('msxpiboot.dsk', 'tools.dsk'):
            shutil.copy(SOFTWARE / 'target/disks' / name, work / f'home{i}/disks' / name)
        shutil.copy(PCHESS, work / 'pchess1.com')
        subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'pchess1.com',
                        f'home{i}/disks/msxpiboot.dsk:PCHESS1.COM'], cwd=work, check=True,
                       stdout=subprocess.DEVNULL)
    fixture = Server(('127.0.0.1', PORTS[2]))
    threading.Thread(target=fixture.serve_forever, daemon=True).start()
    processes, logs = [], []

    def start(args, cwd=None, env=None, name='process'):
        log = (work / f'{name}-{len(processes)}.log').open('w')
        logs.append(log)
        processes.append(subprocess.Popen(args, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT))
        return processes[-1]

    failures = []

    def check(condition, message):
        print(('PASS: ' if condition else 'FAIL: ') + message, flush=True)
        if not condition:
            failures.append(message)

    try:
        for i in range(2):
            env = os.environ.copy()
            env.update(MSXPI_PORT=str(PORTS[i]), MSXPI_HOME=str(work / f'home{i}'), PCHESS_IRC_NICK=NICKS[i],
                       PCHESS_IRC_HOST='127.0.0.1', PCHESS_IRC_PORT=str(PORTS[2]), PCHESS_IRC_TLS='0')
            start([sys.executable, '-u', 'msxpi-server.py'], cwd=SOFTWARE / 'Server/Python/src', env=env, name='server')
        time.sleep(2)
        emulators = []
        for i in range(2):
            script = work / f'client-{i}.tcl'
            script.write_text(tcl_script(i, work))
            emulators.append(start([str(OPENMSX), '-machine', 'National_CF-3300', '-ext', 'MSXPi',
                                    '-command', 'set renderer none', '-script', str(script)], name='openmsx'))
        deadline = time.monotonic() + 240
        while any(p.poll() is None for p in emulators):
            if time.monotonic() > deadline:
                raise RuntimeError('Emulator test timed out')
            time.sleep(.2)

        shown = []
        for i in range(2):
            vram = (work / f'client-{i}-chat.vram').read_bytes()
            rows = chat_lines(vram)
            shown.append(rows)
            print(f'client {i} chat window: {rows}', flush=True)
            check(row(vram, 0)[0] == 'CHAT - ESC OR TAB CLOSES', f'client {i} shows the chat title')
        check(shown[0] == [('YOU: ANYONE HERE', 'public'), ('YOU: HELLO BOB', 'private'),
                           ('BOB: HI ALICE!', 'private')], 'alice sees public white and private yellow rows')
        check(shown[1] == [('ALICE: ANYONE HERE', 'public'), ('ALICE: HELLO BOB', 'private'),
                           ('YOU: HI ALICE!', 'private')], 'bob sees public white and private yellow rows')
        for i in range(2):
            again = chat_lines((work / f'client-{i}-reopened.vram').read_bytes())
            check(again == shown[i], f'client {i} history kept when the window is reopened: {again}')
        unread = (work / 'client-1-unread.vram').read_bytes()
        check(row(unread, 20)[0] == 'ESC MENU  TAB CHAT 2', "bob's panel shows the unread chat count")
        for i in range(2):
            vram = (work / f'client-{i}-closed.vram').read_bytes()
            check(row(vram, 20)[0] == 'ESC MENU  TAB CHAT', f'client {i} unread note cleared')
            want = 'YOU ARE WHITE' if i == 0 else 'YOU ARE BLACK'
            check(row(vram, 2, 18, 14)[0] == want, f'client {i} board panel repainted ({want})')
            # Board tiles are back in characters 0-103: the grid is not text.
            check(vram[NAMTBL + 1 * 32 + 1] < 104 and vram[NAMTBL + 22 * 32] != 0, f'client {i} board redrawn')
        private = [(s, t, m) for s, t, m in fixture.transcript if not m.startswith('PCH1 ')]
        check(('alice', 'bob', 'HELLO BOB') in private, 'alice -> bob went privately')
        check(('bob', 'alice', 'HI ALICE!') in private, 'bob -> alice went privately')
        check(('alice', '#msxpi', 'ANYONE HERE') in private, 'the lobby line went to the public channel')
        check(all(m == 'ANYONE HERE' for _, t, m in private if t == '#msxpi'),
              'nothing else was said on the public channel')
    finally:
        for proc in reversed(processes):
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
        for log in logs:
            log.close()
        fixture.shutdown()
        fixture.server_close()
        print('Test artifacts:', work, flush=True)
    if failures:
        sys.exit(1)


if __name__ == '__main__':
    main()
