"""End-to-end reconnect: two openMSX + two MSXPi servers + the IRC fixture.

Alice and Bob are matched through the lobby and Alice plays e4. The moment
her MOVE reaches the fixture, Bob's IRC link is cut from the server side and
his nick stays held for a few seconds, as on a real IRC server. Bob's screen
must show that the link is lost, his MSXPi server must dial again with the
same nick, and his reply (e5) must then go through to Alice, with no PEER
TIMEOUT on either side.

    python pchess_reconnect_openmsx.py [path\\to\\pchess.com]

Same requirements as pchess_chat_openmsx.py. Ports 5041, 5042 and 5081.
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
sys.path.insert(0, str(HERE))
import pchess_chat_openmsx as base  # noqa: E402
from pchess_tcpip_openmsx import text_at  # noqa: E402
from pchess_irc_fixture import Server  # noqa: E402

GHOST_SECONDS = 25
# (emulated seconds, keys) per player after the common boot to DOS (28 s).
# Alice moves at 74; Bob's link drops as soon as it is seen; Bob answers at 118.
base.KEYS = (
    [(38, '5'), (51, '6'), (55, '7'), (57, 'bob\\r'), (74, 'e2e4\\r'),
     (130, 'dump:final'), (132, 'quit')],
    [(38, '5'), (64, '8'), (92, 'dump:lost'), (118, 'e7e5\\r'), (130, 'dump:final'), (132, 'quit')],
)


def main():
    for port in base.PORTS:
        with socket.socket() as probe:
            if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            probe.bind(('127.0.0.1', port))
    work = Path(tempfile.mkdtemp(prefix='pchess-reconnect-'))
    floppy = work / 'floppy'
    shutil.copytree(base.FLOPPY, floppy)
    shutil.copy(base.PCHESS, floppy / 'pchess.com')
    fixture = Server(('127.0.0.1', base.PORTS[2]))
    fixture.ghost_delay = GHOST_SECONDS
    threading.Thread(target=fixture.serve_forever, daemon=True).start()
    processes, logs = [], []
    failures = []

    def start(args, cwd=None, env=None, name='process'):
        log = (work / f'{name}-{len(processes)}.log').open('w')
        logs.append(log)
        processes.append(subprocess.Popen(args, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT))
        return processes[-1]

    def check(condition, message):
        print(('PASS: ' if condition else 'FAIL: ') + message, flush=True)
        if not condition:
            failures.append(message)

    dropped = []

    def dropper():
        # Cut Bob off once Alice's first MOVE has crossed the fixture.
        while not dropped:
            if any(m.startswith('PCH1 MOVE') for s, t, m in list(fixture.transcript) if s == 'alice'):
                link = fixture.clients.get('bob')
                if link:
                    link.connection.shutdown(2)
                    dropped.append(time.monotonic())
            time.sleep(.05)

    try:
        for i in range(2):
            env = os.environ.copy()
            env.update(MSXPI_PORT=str(base.PORTS[i]), PCHESS_IRC_NICK=base.NICKS[i], PCHESS_IRC_HOST='127.0.0.1',
                       PCHESS_IRC_PORT=str(base.PORTS[2]), PCHESS_IRC_TLS='0', PCHESS_IRC_TRACE='1')
            start([sys.executable, '-u', 'msxpi-server.py'], cwd=base.SOFTWARE / 'Server/Python/src', env=env, name='server')
        time.sleep(2)
        threading.Thread(target=dropper, daemon=True).start()
        emulators = []
        for i in range(2):
            script = work / f'client-{i}.tcl'
            script.write_text(base.tcl_script(i, work))
            emulators.append(start([str(base.OPENMSX), '-machine', 'Panasonic_FS-A1WSX', '-ext', 'MSXPi',
                                    '-ext', 'ram4mb', '-diska', str(floppy), '-script', str(script)], name='openmsx'))
        deadline = time.monotonic() + 240
        while any(p.poll() is None for p in emulators):
            if time.monotonic() > deadline:
                raise RuntimeError('Emulator test timed out')
            time.sleep(.2)

        check(bool(dropped), "bob's link was cut after alice's move")
        lost = (work / 'client-1-lost.vram').read_bytes()
        status = text_at(lost, 8, 205, 40)
        print('bob status while away:', status, flush=True)
        check(status.startswith('IRC LINK LOST'), "bob's screen says the link is lost and reconnecting")
        for i in range(2):
            vram = (work / f'client-{i}-final.vram').read_bytes()
            moves = [text_at(vram, 206, 41 + n * 9, 8) for n in range(2)]
            check(moves == ['E4', 'E5'], f'client {i} shows e4 e5: {moves}')
            check('TIMEOUT' not in text_at(vram, 8, 205, 40), f'client {i} no PEER TIMEOUT')
        bob_log = next(work.glob('server-1.log')).read_text(errors='replace')
        print(bob_log[-600:], flush=True)
        check('LINK LOST' in bob_log and 'LINK RESTORED' in bob_log, "bob's server logged the redial and the restore")
        check(any(s == 'bob' and m.startswith('PCH1 MOVE') for s, t, m in fixture.transcript), 'bob move reached alice')
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
