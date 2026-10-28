"""PCheckers over the MSXPi link with IRC rooms and the IRC lobby, in openMSX.

The MSXPi server runs with PCHESSROOMS=irc against the pchess IRC fixture. Two
scenarios, each with one emulated MSX and scripted IRC players (the very IRC
classes an MSXPi server uses):

  room   The MSX joins room "dama" (key 4) where Alice (PCheckers) and Carl (a
         PChess player) already are. Alice, the lower nick, plays white and
         moves C3-D4; the MSX answers B6-A5. Carl's talk in the room is public
         and reaches the MSX; Alice and the MSX then talk privately and Carl
         hears neither the chat nor any game line.
  lobby  The MSX goes online (key 5). Dave seeks, the MSX sees it (key 9
         lists him), invites him (key 7), Dave accepts and the MSX plays white.

    python pcheckers_irc_openmsx.py [room|lobby] [path/to/pcheckers.com]
"""
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(SOFTWARE / 'Server/Python/src'))
sys.path.insert(0, str(SOFTWARE / 'Server/Python/tests'))
from pchess_irc_fixture import Server  # noqa: E402
from msxpi_game_irc import IRC  # noqa: E402
from msxpi_pcheckers_irc import CheckersPeer  # noqa: E402
from pchess_chat_openmsx import chat_lines  # noqa: E402
from pchess_tcpip_openmsx import text_at  # noqa: E402

SCENARIO = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] in ('room', 'lobby') else 'room'
args = [a for a in sys.argv[1:] if a not in ('room', 'lobby')]
OPENMSX = Path(os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.7.0/openmsx.exe'))
FLOPPY = Path(os.environ.get('FLOPPYA', 'C:/Users/roniv/Dev/MSX/MSXPi/FloppyA'))
PROGRAM = Path(args[0] if args else SOFTWARE / 'target/pcheckers.com')
IRC_PORT, MSXPI_PORT = 6668, 5044
RIGHT, LEFT, UP, DOWN, TAB, ESC = '\\x1c', '\\x1d', '\\x1e', '\\x1f', '\\t', '\\x1b'

ROOM = [(38, '4'), (40, 'dama\\r'),
        (60, RIGHT), (60.5, RIGHT), (61, RIGHT), (61.5, DOWN), (62, DOWN), (62.5, DOWN), (63, ' '),
        (63.5, RIGHT), (64, UP), (64.5, ' '), (72, 'dump:moved'),
        (74, TAB), (80, 'dump:chat'), (81, 'hi alice\\r'), (86, 'dump:chat-sent'), (88, ESC), (92, 'quit')]
# The MSX is white in the lobby: the cursor starts on E3, F4 is one right and one up.
LOBBY = [(38, '5'), (52, 'dump:seeked'), (53, '9'), (54.5, 'dump:players'), (55, ESC),
         (56, '7'), (57, 'Dave\\r'), (72, 'dump:matched'),
         (74, ' '), (74.5, RIGHT), (75, UP), (75.5, ' '), (84, 'dump:moved'), (86, 'quit')]
TIMELINE = ROOM if SCENARIO == 'room' else LOBBY


def write_script(path, dumps):
    lines = ['set save_settings_on_exit off', f'set msxpiserver_port {MSXPI_PORT}',
             'set speed 100', 'set power on', 'set pause off',
             'proc dump {name} {',
             f'    set f [open "{dumps.as_posix()}/$name.vram" w]',
             '    fconfigure $f -translation binary',
             '    puts -nonewline $f [debug read_block VRAM 0 27136]',
             '    close $f', '}',
             'after time 23 {type_via_keybuf "c:\\r"}',
             'after time 28 {type_via_keybuf "pcheckers\\r"}']
    for when, action in TIMELINE:
        if action.startswith('dump:'):
            lines.append(f'after time {when} {{dump {action[5:]}}}')
        elif action == 'quit':
            lines.append(f'after time {when} {{exit}}')
        else:
            lines.append(f'after time {when} {{type_via_keybuf "{action}"}}')
    path.write_text('\n'.join(lines) + '\n')


class Player(threading.Thread):
    """An IRC client of the kind an MSXPi server runs, driven by a script."""

    def __init__(self, nick, room, peer_class, script):
        super().__init__(daemon=True)
        os.environ['PCHESS_IRC_NICK'] = nick
        self.irc = IRC(None, room, peer_class)
        self.nick, self.script, self.error, self.done = nick, script, None, False
        self.heard, self.started = [], time.monotonic()

    def run(self):
        try:
            while not self.done:
                self.irc.poll()
                self.heard.extend(self.irc.peer.take_chat()[0])
                self.script(self, time.monotonic() - self.started)
                time.sleep(.2)
        except Exception as exc:
            self.error = exc


def main():
    work = Path(tempfile.mkdtemp(prefix=f'pcheckers-irc-{SCENARIO}-'))
    floppy, dumps = work / 'floppy', work / 'vram'
    shutil.copytree(FLOPPY, floppy)
    dumps.mkdir()
    shutil.copy(PROGRAM, floppy / 'pcheckers.com')
    write_script(work / 'msx.tcl', dumps)
    irc = Server(('127.0.0.1', IRC_PORT))
    threading.Thread(target=irc.serve_forever, daemon=True).start()
    os.environ.update(PCHESS_IRC_HOST='127.0.0.1', PCHESS_IRC_PORT=str(IRC_PORT), PCHESS_IRC_TLS='0')
    state = {}
    players = []

    def alice(me, t):
        peer = me.irc.peer
        if peer.phase == 'playing' and 'moved' not in state and peer.side == 0:
            peer.cmove(0, 'c3d4')
            state['moved'] = True
        if peer.phase == 'playing' and 'greeted' not in state and peer.moves:
            peer.say('good luck msx')
            state['greeted'] = True

    def carl(me, t):
        if 'MsxOne' in irc.channels.get('#pchess-dama', ()) and 'said' not in state:
            me.irc.peer.say('ola sala')
            state['said'] = True

    def dave(me, t):
        peer = me.irc.peer
        if me.irc.ready and 'sought' not in state and 'MsxOne' in irc.channels.get('#msxpi', ()):
            peer.seek()
            state['sought'] = True
        if peer.invite and peer.phase != 'playing':
            peer.accept()

    if SCENARIO == 'room':
        players = [Player('Alice', '#pchess-dama', CheckersPeer, alice),
                   Player('Carl', '#pchess-dama', None, carl)]
    else:
        players = [Player('Dave', None, CheckersPeer, dave)]
    for p in players:
        p.start()

    env = dict(os.environ, MSXPI_PORT=str(MSXPI_PORT), PCHESS_ROOMS='irc', PCHESS_IRC_NICK='MsxOne')
    log = (work / 'server.log').open('w')
    server = subprocess.Popen([sys.executable, '-u', 'msxpi-server.py'], env=env,
                              cwd=SOFTWARE / 'Server/Python/src', stdout=log, stderr=subprocess.STDOUT)
    try:
        time.sleep(3)
        with (work / 'openmsx.log').open('w') as out:
            subprocess.run([str(OPENMSX), '-machine', 'Panasonic_FS-A1WSX', '-ext', 'MSXPi', '-ext', 'ram4mb',
                            '-diska', str(floppy), '-script', str(work / 'msx.tcl')],
                           stdout=out, stderr=subprocess.STDOUT, timeout=300)
    finally:
        for p in players:
            p.done = True
        server.terminate()
        server.wait()
        log.close()

    failures = []

    def check(name, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + name + (' - ' + str(detail) if detail and not ok else ''))
        if not ok:
            failures.append(name)

    def screen(name):
        path = dumps / f'{name}.vram'
        return path.read_bytes() if path.exists() else b'\0' * 27136

    def status(v):
        return text_at(v, 8, 205, 41)

    def moves(v):
        return [text_at(v, 206, 41 + i * 9, 8) for i in range(2)]

    if SCENARIO == 'room':
        a, c = players
        v = screen('moved')
        check('MSX is black and sees both moves', text_at(v, 206, 2, 8) == 'AS BLACK' and moves(v) == ['C3-D4', 'B6-A5'],
              (text_at(v, 206, 2, 8), moves(v), status(v)))
        check('alice got the MSX move', a.irc.peer.moves == ['c3d4', 'b6a5'], a.irc.peer.moves)
        rows = chat_lines(screen('chat'))
        check('public room talk white, private talk yellow',
              rows == [('CARL: OLA SALA', 'public'), ('ALICE: GOOD LUCK MSX', 'private')], rows)
        rows = chat_lines(screen('chat-sent'))
        check('answer shown', rows[-1:] == [('YOU: HI ALICE', 'private')], rows)
        check('alice heard it privately', (1, 'MSXONE: HI ALICE') in a.heard, a.heard)
        check('carl never hears the private game', c.heard == [], c.heard)
        check('no player errors', not a.error and not c.error, (a.error, c.error))
    else:
        d = players[0]
        check('seek announced', status(screen('seeked')).startswith('PLAYER DAVE'), status(screen('seeked')))
        v = screen('players')
        check('players window lists dave', text_at(v, 44 + 8 + 12, 56 + 16, 10).endswith('Dave'.upper()) or
              'DAVE' in text_at(v, 44 + 8, 56 + 16, 18), text_at(v, 52, 72, 18))
        v = screen('matched')
        check('MSX is white after the invitation', text_at(v, 206, 2, 8) == 'AS WHITE', (text_at(v, 206, 2, 8), status(v)))
        v = screen('moved')
        check('white move F4 played', moves(v)[0] == 'E3-F4', moves(v))
        check('dave got the move', d.irc.peer.moves == ['e3f4'], d.irc.peer.moves)
        check('no player errors', not d.error, d.error)
    print('artefacts in', work)
    irc.shutdown()
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
