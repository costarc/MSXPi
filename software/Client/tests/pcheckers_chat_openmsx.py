"""End-to-end PCheckers online: two openMSX + two MSXPi servers sharing one relay.

Alice (white) and Bob (black) join room "dama" with key 4. Alice plays E3-F4
with the cursor, Bob answers B6-A5 on his rotated board, then both chat in the
TAB window. Screens are read back from VRAM with the shared PChess font.

    python pcheckers_chat_openmsx.py [path/to/pcheckers.com]

Windows Python with python-chess, openMSX v1.6.1 with the MSXPi extension and
the FloppyA disk (copied). Ports 5041, 5042 and 5080 must be free.
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[1]
sys.path.insert(0, str(HERE))
from pchess_chat_openmsx import chat_lines  # noqa: E402
from pchess_tcpip_openmsx import text_at  # noqa: E402

OPENMSX = Path(os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe'))
FLOPPY = Path(os.environ.get('FLOPPYA', 'C:/Users/roniv/Dev/MSX/MSXPi/FloppyA'))
PROGRAM = Path(sys.argv[1] if len(sys.argv) > 1 else SOFTWARE / 'target/pcheckers.com')
PORTS = (5041, 5042, 5080)
RIGHT, LEFT, UP, DOWN = '\\x1c', '\\x1d', '\\x1e', '\\x1f'
TAB = '\\t'


def keys_for(*steps):
    return list(steps)


ALICE = [(38, '4'), (40, 'dama\\r'),
         (52, ' '), (53, RIGHT), (54, UP), (55, ' '), (79, 'dump:moved'),
         (80, TAB), (82, 'hello bob\\r'), (96, 'dump:chat'), (98, '\\x1b'), (100, 'dump:closed'), (102, 'quit')]
BOB = [(38, '4'), (46, 'dama\\r'),
       (70, RIGHT), (70.5, RIGHT), (71, RIGHT), (71.5, DOWN), (72, DOWN), (72.5, DOWN), (73, ' '),
       (73.5, RIGHT), (74, UP), (74.5, ' '), (79, 'dump:moved'),
       (84, TAB), (90, 'hi alice\\r'), (96, 'dump:chat'), (98, '\\x1b'), (100, 'dump:closed'), (102, 'quit')]


def tcl_script(index, work):
    lines = ['set save_settings_on_exit off', f'set msxpiserver_port {PORTS[index]}',
             'set speed 100', 'set power on', 'set pause off',
             'proc dump {name} {',
             f'    set f [open "{work.as_posix()}/client-{index}-$name.vram" w]',
             '    fconfigure $f -translation binary',
             '    puts -nonewline $f [debug read_block VRAM 0 27136]',
             '    close $f', '}',
             'after time 23 {type_via_keybuf "c:\\r"}',
             'after time 25 {type_via_keybuf "dir pcheckers.com\\r"}',
             'after time 28 {type_via_keybuf "pcheckers\\r"}', f'after time 60 {{screenshot {work.as_posix()}/s{index}a.png}}', f'after time 79.5 {{screenshot {work.as_posix()}/s{index}b.png}}']
    for when, action in (ALICE, BOB)[index]:
        if action.startswith('dump:'):
            lines.append(f'after time {when} {{dump {action[5:]}}}')
        elif action == 'quit':
            lines.append(f'after time {when} {{exit}}')
        else:
            lines.append(f'after time {when} {{type_via_keybuf "{action}"}}')
    return '\n'.join(lines) + '\n'


def main():
    for port in PORTS:
        with socket.socket() as probe:
            if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            probe.bind(('127.0.0.1', port))
    work = Path(tempfile.mkdtemp(prefix='pcheckers-chat-'))
    floppy = work / 'floppy'
    shutil.copytree(FLOPPY, floppy)
    shutil.copy(PROGRAM, floppy / 'pcheckers.com')
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
            env.update(MSXPI_PORT=str(PORTS[i]), PCHESS_ROOMS='relay', PCHESS_RELAY_URL=f'http://127.0.0.1:{PORTS[2]}')
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

        for i, label in enumerate(('alice', 'bob')):
            vram = (work / f'client-{i}-moved.vram').read_bytes()
            moves = [text_at(vram, 206, 41 + n * 9, 8) for n in range(3)]
            check(moves[:2] == ['E3-F4', 'B6-A5'], f'{label} sees both moves: {moves}')
            check(text_at(vram, 206, 2, 8) == ('AS WHITE' if i == 0 else 'AS BLACK'), f'{label} panel shows the side')
            check(text_at(vram, 8, 205, 24) == ('YOUR MOVE' if i == 0 else 'OPPONENT MOVES'),
                  f'{label} status: {text_at(vram, 8, 205, 24)}')
        shown = [chat_lines((work / f'client-{i}-chat.vram').read_bytes()) for i in range(2)]
        print('chat windows:', shown, flush=True)
        check(shown[0] == [('YOU: HELLO BOB', 'private'), ('BLACK: HI ALICE', 'private')], 'alice chat rows')
        check(shown[1] == [('WHITE: HELLO BOB', 'private'), ('YOU: HI ALICE', 'private')], 'bob chat rows')
        for i in range(2):
            vram = (work / f'client-{i}-closed.vram').read_bytes()
            check(text_at(vram, 206, 197, 8) == 'ESC MENU', f'client {i} board repainted, unread cleared')
    finally:
        for proc in reversed(processes):
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
        for log in logs:
            log.close()
        print('Test artifacts:', work, flush=True)
    if failures:
        sys.exit(1)


if __name__ == '__main__':
    main()
