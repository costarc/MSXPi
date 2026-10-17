"""End-to-end chat: two openMSX + two MSXPi servers + the IRC fixture.

Alice and Bob are matched through the lobby (5 ONLINE, SEEK, ASK, ACCEPT).
Alice then opens the chat window with TAB and says "hello bob"; Bob opens it,
sees her line arrive by polling, and answers "hi alice!". Both screens are
read back from VRAM with PChess's own font, then ESC closes the window and
the board must be repainted. The IRC fixture's transcript shows the chat went
privately between the players and never to #msxpi.

    python pchess_chat_openmsx.py [path\\to\\pchess.com]

Windows Python with python-chess, openMSX with the MSXPi extension and the
FloppyA disk (copied, so the original pchess.com is not replaced). Ports 5041,
5042 and 5081 must be free.
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
sys.path.insert(0, str(SOFTWARE / 'Server/Python/src'))
sys.path.insert(0, str(SOFTWARE / 'Server/Python/tests'))
sys.path.insert(0, str(HERE))
from pchess_irc_fixture import Server  # noqa: E402
from pchess_tcpip_openmsx import FONT, text_at  # noqa: E402

OPENMSX = Path(os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6/openmsx.exe'))
FLOPPY = Path(os.environ.get('FLOPPYA', 'C:/Users/roniv/Dev/MSX/MSXPi/FloppyA'))
PCHESS = Path(sys.argv[1] if len(sys.argv) > 1 else os.environ.get('PCHESS_COM', SOFTWARE / 'target/pchess.com'))
PORTS = (5041, 5042, 5081)
NICKS = ('alice', 'bob')
CHAT_TOP, CHAT_ROWS = 12, 20

TAB = '\\t'
# (emulated seconds, keys) per player, after the common boot to DOS (28 s).
KEYS = (
    # Alice speaks in the lobby first (public), then gets matched with Bob. Both
    # close the window at 98 and open it again at 100: the history stays.
    [(38, '5'), (44, TAB), (46, 'anyone here\\r'), (49, '\\x1b'), (51, '6'), (55, '7'),
     (57, 'bob\\r'), (68, TAB), (70, 'hello bob\\r'), (94, 'dump:chat'),
     (98, '\\x1b'), (100, TAB), (104, 'dump:reopened'), (106, '\\x1b'), (110, 'dump:closed'), (112, 'quit')],
    # Bob lets the lines arrive while he is still looking at the board.
    [(38, '5'), (64, '8'), (78, 'dump:unread'), (82, TAB), (86, 'hi alice!\\r'), (94, 'dump:chat'),
     (98, '\\x1b'), (100, TAB), (104, 'dump:reopened'), (106, '\\x1b'), (110, 'dump:closed'), (112, 'quit')],
)


def tcl_script(index, work):
    lines = ['set save_settings_on_exit off', f'set msxpiserver_port {PORTS[index]}',
             'set speed 100', 'set power on', 'set pause off',
             'proc dump {name} {',
             f'    set f [open "{work.as_posix()}/client-{index}-$name.vram" w]',
             '    fconfigure $f -translation binary',
             '    puts -nonewline $f [debug read_block VRAM 0 27136]',
             '    close $f', '}',
             'after time 23 {type_via_keybuf "c:\\r"}',
             'after time 25 {type_via_keybuf "dir pchess.com\\r"}',
             'after time 28 {type_via_keybuf "pchess\\r"}']
    for when, action in KEYS[index]:
        if action.startswith('dump:'):
            lines.append(f'after time {when} {{dump {action[5:]}}}')
        elif action == 'quit':
            lines.append(f'after time {when} {{exit}}')
        else:
            lines.append(f'after time {when} {{type_via_keybuf "{action}"}}')
    return '\n'.join(lines) + '\n'


WHITE, YELLOW = 15, 11


def row_text(vram, y, x=2, count=42):
    """Text of one chat row and the set of colours its lit pixels use."""
    out, colours = '', set()
    for n in range(count):
        left = x + n * 6
        if left + 5 > 255:
            break
        rows = []
        for r in range(7):
            bits = 0
            for c in range(5):
                px = left + c
                byte = vram[(y + r) * 128 + px // 2]
                value = (byte >> 4) if px % 2 == 0 else (byte & 15)
                if value in (WHITE, YELLOW):
                    bits |= 0x10 >> c
                    colours.add(value)
            rows.append(bits)
        out += FONT.get(tuple(rows), '?')
    return out.rstrip(), colours


def chat_lines(vram):
    """[(text, 'public' | 'private')] for the rows that are not empty."""
    rows = []
    for i in range(CHAT_ROWS):
        text, colours = row_text(vram, CHAT_TOP + i * 9)
        if text:
            rows.append((text, 'private' if colours == {YELLOW} else 'public' if colours == {WHITE} else 'mixed'))
    return rows


def main():
    for port in PORTS:
        with socket.socket() as probe:
            if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            probe.bind(('127.0.0.1', port))
    work = Path(tempfile.mkdtemp(prefix='pchess-chat-'))
    floppy = work / 'floppy'
    shutil.copytree(FLOPPY, floppy)
    shutil.copy(PCHESS, floppy / 'pchess.com')
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
            env.update(MSXPI_PORT=str(PORTS[i]), PCHESS_IRC_NICK=NICKS[i], PCHESS_IRC_HOST='127.0.0.1',
                       PCHESS_IRC_PORT=str(PORTS[2]), PCHESS_IRC_TLS='0')
            start([sys.executable, '-u', 'msxpi-server.py'], cwd=SOFTWARE / 'Server/Python/src', env=env, name='server')
        time.sleep(2)
        emulators = []
        for i in range(2):
            script = work / f'client-{i}.tcl'
            script.write_text(tcl_script(i, work))
            emulators.append(start([str(OPENMSX), '-machine', 'Panasonic_FS-A1WSX', '-ext', 'MSXPi',
                                    '-ext', 'ram4mb', '-diska', str(floppy), '-script', str(script)], name='openmsx'))
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
            check(text_at(vram, 2, 1, 24) == 'CHAT - ESC OR TAB CLOSES', f'client {i} shows the chat title')
        # Public lobby talk is white; once matched, everything is private and yellow.
        check(shown[0] == [('YOU: ANYONE HERE', 'public'), ('YOU: HELLO BOB', 'private'),
                           ('BOB: HI ALICE!', 'private')], 'alice sees public white and private yellow rows')
        check(shown[1] == [('ALICE: ANYONE HERE', 'public'), ('ALICE: HELLO BOB', 'private'),
                           ('YOU: HI ALICE!', 'private')], 'bob sees public white and private yellow rows')

        for i in range(2):
            again = chat_lines((work / f'client-{i}-reopened.vram').read_bytes())
            check(again == shown[i], f'client {i} history kept when the window is reopened: {again}')
        unread = (work / 'client-1-unread.vram').read_bytes()
        check(text_at(unread, 206, 197, 8) == 'CHAT 2', "bob's panel shows the unread chat count")
        for i in range(2):
            vram = (work / f'client-{i}-closed.vram').read_bytes()
            check(text_at(vram, 206, 197, 8) == 'ESC MENU', f'client {i} unread note cleared')
            colour = 'AS WHITE' if i == 0 else 'AS BLACK'
            check(text_at(vram, 206, 2, 8) == colour, f'client {i} board panel repainted ({colour})')
            # The chat window's yellow rules (colour 11) at y=9 and y=196 are gone from the panel columns.
            check(all(vram[y * 128 + x] == 0x11 for y in (9, 196) for x in range(102, 128)),
                  f'client {i} chat window cleared')
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
