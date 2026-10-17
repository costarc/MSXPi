"""End-to-end chat: two openMSX + two MSXPi servers + the IRC fixture.

Alice and Bob are matched through the lobby (4 ONLINE, SEEK, ASK, ACCEPT).
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
from pchess_tcpip_openmsx import text_at  # noqa: E402

OPENMSX = Path(os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6/openmsx.exe'))
FLOPPY = Path(os.environ.get('FLOPPYA', 'C:/Users/roniv/Dev/MSX/MSXPi/FloppyA'))
PCHESS = Path(sys.argv[1] if len(sys.argv) > 1 else os.environ.get('PCHESS_COM', SOFTWARE / 'target/pchess.com'))
PORTS = (5041, 5042, 5081)
NICKS = ('alice', 'bob')
CHAT_TOP, CHAT_ROWS = 12, 20

TAB = '\\t'
# (emulated seconds, keys) per player, after the common boot to DOS (28 s).
KEYS = (
    [(38, '4'), (44, '5'), (48, '6'), (50, 'bob\\r'), (66, TAB), (68, 'hello bob\\r'), (92, 'dump:chat'),
     (96, '\\x1b'), (100, 'dump:closed'), (102, 'quit')],
    # Bob lets the line arrive while he is still looking at the board.
    [(38, '4'), (57, '7'), (76, 'dump:unread'), (80, TAB), (84, 'hi alice!\\r'), (92, 'dump:chat'),
     (96, '\\x1b'), (100, 'dump:closed'), (102, 'quit')],
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


def chat_lines(vram):
    return [text_at(vram, 2, CHAT_TOP + i * 9, 42) for i in range(CHAT_ROWS)]


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
            rows = [r for r in chat_lines(vram) if r]
            shown.append(rows)
            print(f'client {i} chat window: {rows}', flush=True)
            check(text_at(vram, 2, 1, 24) == 'CHAT - ESC OR TAB CLOSES', f'client {i} shows the chat title')
        check('YOU: HELLO BOB' in shown[0], 'alice sees her own line')
        check('BOB: HI ALICE!' in shown[0], 'alice receives bob\'s answer')
        check('ALICE: HELLO BOB' in shown[1], 'bob receives alice\'s line')
        check('YOU: HI ALICE!' in shown[1], 'bob sees his own line')

        unread = (work / 'client-1-unread.vram').read_bytes()
        check(text_at(unread, 206, 197, 8) == 'CHAT 1', "bob's panel shows the unread chat count")
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
        check(all(t != '#msxpi' for _, t, m in private), 'no chat on the public channel')
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
