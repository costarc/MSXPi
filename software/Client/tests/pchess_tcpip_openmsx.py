"""End-to-end: PCHESS.COM on TCP/IP UNAPI in openMSX against MSXPi players.

The emulated MSX (Canon V-25 + 2 MB mapper + MSXPi, MSX-DOS 1) runs MSR I
and INL I, starts PCHESS, switches LINK to TCPIP in the ESC menu and then:

  1. plays a LOCAL game (rules checked on the MSX),
  2. joins ROOM club7 over IRC, where "Alice" waits - Alice is the same
     msxpi_pchess_irc.IRC client an MSXPi server runs, so this is cross-play,
  3. goes ONLINE: seeks in #msxpi, accepts "Bob"'s invitation, plays, and
     accepts Bob's draw offer from the ESC menu,
  4. exits to DOS.

The IRC server is pchess_irc_fixture on this host; the MSX reaches it at
192.168.99.1 through the Windows TAP (msxpi-tcpip-setup.ps1). The screen is
SCREEN 5, so its text is read back from VRAM with PChess's own font.

    python pchess_tcpip_openmsx.py
Needs Windows Python with python-chess, the TAP set up, and port 5000 and
6667 free. Artefacts go to <repo>/../work/pchess-tcpip-*/.
"""
import os
import re
import shutil
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
from pchess_irc_fixture import Server  # noqa: E402
from msxpi_pchess_irc import IRC  # noqa: E402

OPENMSX = os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6/openmsx.exe')
PCHESS = Path(os.environ.get('PCHESS_COM', SOFTWARE / 'target/pchess.com'))
IRC_PORT = 6667
ROOM = '#pchess-club7'


# --- screen text ----------------------------------------------------------

def load_font():
    src = (SOFTWARE / 'Client/src/pchess.c').read_text()
    font = {}
    for rows, ch in re.findall(r'\{((?:0x[0-9A-F]{2},){6}0x[0-9A-F]{2})\}, /\* (.) \*/', src):
        font[tuple(int(v, 16) for v in rows.split(','))] = ch
    return font


FONT = load_font()


def text_at(vram, x, y, count=41):
    out = ''
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
                if ((byte >> 4) if px % 2 == 0 else (byte & 15)) == 15:
                    bits |= 0x10 >> c
            rows.append(bits)
        out += FONT.get(tuple(rows), '?')
    return out.rstrip()


def screen_report(vram):
    lines = {'status': text_at(vram, 8, 205)}
    for label, y in (('title', 2), ('turn', 12), ('state', 21)):
        lines[label] = text_at(vram, 206, y, 8)
    lines['moves'] = [text_at(vram, 206, 41 + i * 9, 8) for i in range(8)]
    return lines


# --- the MSX's script -----------------------------------------------------

ESC, DOWN, RIGHT = chr(27), chr(31), chr(28)
HW = os.environ.get('HW', 'msxpi')
# Getting to PCHESS, per hardware profile; the game timeline follows it.
# msxpi: MSX-DOS 1 from the MSXPi disk, mapper from ram2mb: MSR I, INL I.
# nextor: MegaFlashROM SCC+ SD booting Nextor (MSX-DOS 2) from its own SD
# card; AUTOEXEC starts MultiMente (ESC, Return leaves it). The MSXPi disk
# is drive D:, where RAMHELPR I and INL I run; RAMHELPR restarts the
# command interpreter, which goes back to A:.
PREFIX = {
    'msxpi': ([(20, 'MSR I\r'), (32, 'INL I\r'), (50, 'PCHESS\r')], 0),
    # MultiMente reads the key matrix: the keyboard buffer never reaches it.
    'nextor': ([(30, 'press:7:4'), (33, 'press:7:128'), (36, 'press:7:4'), (39, 'press:7:128'),
                (44, 'D:\r'), (48, 'RAMHELPR I\r'), (54, 'D:\r'), (58, 'INL I\r'), (78, 'PCHESS\r')], 28),
}
GAME = [
    # ESC menu: LINK is the third row; right toggles it, Return applies.
    (66, ESC), (69, DOWN + DOWN + RIGHT + '\r'), (74, 'dump:link'),
    # 1. LOCAL game, rules on the MSX.
    (76, 'e4\r'), (80, 'e5\r'), (84, 'Nf3\r'), (88, 'Qh5\r'), (92, 'dump:local'),
    # 2. ROOM club7 over IRC: Alice (lower nick) offers and plays white.
    (94, chr(8) * 4), (95, '3'), (97, 'club7\r'), (125, 'dump:room-matched'),
    (140, 'e5\r'), (165, 'Nc6\r'), (190, 'dump:room-end'),
    # 3. ONLINE lobby: leave the room (Y), seek, accept Bob, play, draw.
    (193, '4y'), (215, '5'), (232, '7'), (255, 'dump:lobby-matched'),
    (262, 'd5\r'), (285, 'dump:draw-offered'),
    (288, ESC), (291, DOWN * 3 + '\r'), (293, 'y'), (300, 'dump:draw-agreed'),
    # 4. EXIT is the last menu row.
    (303, ESC), (306, DOWN * 7 + '\r'), (315, 'quit'),
]
TIMELINE = PREFIX[HW][0] + [(t + PREFIX[HW][1], a) for t, a in GAME]


def tcl_string(text):
    return ''.join(c if c.isalnum() or c in ' ' else '\\x%02x' % ord(c) for c in text)


def write_script(path, dumps):
    lines = ['set save_settings_on_exit off', 'set speed 100', 'set power on',
             'proc dump {name} {',
             f'    set f [open "{dumps.as_posix()}/$name.vram" w]',
             '    fconfigure $f -translation binary',
             '    puts -nonewline $f [debug read_block VRAM 0 32768]',
             '    close $f', '}']
    for when, action in TIMELINE:
        if action == 'quit':
            lines.append(f'after time {when} {{dump final; exit}}')
        elif action.startswith('press:'):
            _, row, bit = action.split(':')
            lines.append(f'after time {when} {{keymatrixdown {row} {bit}; '
                         f'after time 0.3 {{keymatrixup {row} {bit}}}}}')
        elif action.startswith('dump:'):
            lines.append(f'after time {when} {{dump {action[5:]}}}')
        else:
            lines.append(f'after time {when} {{type_via_keybuf "{tcl_string(action)}"}}')
    path.write_text('\n'.join(lines) + '\n')


# --- MSXPi-side players ---------------------------------------------------

class Player(threading.Thread):
    """An MSXPi server's IRC client, scripted: plays 'moves' in turn, then
    does 'finish' ('resign' or 'draw') once 'after' plies are on the board."""

    def __init__(self, nick, room, moves, finish, after, log):
        super().__init__(daemon=True)
        os.environ.update(PCHESS_IRC_HOST='127.0.0.1', PCHESS_IRC_PORT=str(IRC_PORT),
                          PCHESS_IRC_TLS='0', PCHESS_IRC_NICK=nick, PCHESS_IRC_TRACE='0')
        self.irc = IRC(None, room)
        self.nick, self.moves, self.finish, self.after, self.log = nick, list(moves), finish, after, log
        self.done = False
        self.error = None

    def say(self, text):
        self.log.append(f'{time.strftime("%H:%M:%S")} {self.nick}: {text}')

    def run(self):
        peer = self.irc.peer
        last = None
        try:
            while not self.done:
                state = self.irc.poll()
                if state['status'] != last:
                    last = state['status']
                    self.say(last)
                if self.irc.ready and not peer.room and peer.phase == 'lobby':
                    names = peer.recent_players()
                    if names:
                        self.say('offering ' + names[0])
                        peer.offer(names[0])
                if peer.phase == 'playing' and not peer.pending and peer.result is None:
                    plies = len(peer.board.move_stack)
                    if plies >= self.after and self.finish:
                        if self.finish == 'resign':
                            peer.resign()
                        elif peer.board.turn == peer.side and peer.draw_offer != 'me':
                            peer.draw()
                        if peer.draw_offer == 'me' or peer.result is not None:
                            self.say('finished: ' + self.finish)
                            self.finish = None
                    elif peer.board.turn == peer.side and self.moves:
                        move = self.moves.pop(0)
                        self.say('move ' + move)
                        peer.move(move)
                time.sleep(.2)
        except Exception as exc:  # reported by the main thread
            self.error = exc
            self.say('ERROR ' + repr(exc))


# --- run ------------------------------------------------------------------

def main():
    (SOFTWARE.parent / 'work').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='pchess-tcpip-', dir=SOFTWARE.parent / 'work'))
    home, dumps = work / 'home', work / 'vram'
    (home / 'disks').mkdir(parents=True)
    dumps.mkdir()
    disk = home / 'disks/msxpiboot.dsk'
    shutil.copy(SOFTWARE / 'target/disks/msxpiboot.dsk', disk)
    shutil.copy(SOFTWARE / 'target/disks/tools.dsk', home / 'disks/tools.dsk')
    (work / 'PCHESS.INI').write_bytes(b'IRCADDR=192.168.99.1\r\nIRCPORT=6667\r\nIRCNICK=MsxOne\r\n')
    shutil.copy(PCHESS, work / 'pchess.com')
    script = work / 'pchess.tcl'
    for name, target in (('pchess.com', 'PCHESS.COM'), ('PCHESS.INI', 'PCHESS.INI')):
        subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', name,
                        f'home/disks/msxpiboot.dsk:{target}'], cwd=work, check=True,
                       stdout=subprocess.DEVNULL)
    machine = (['-ext', 'MegaFlashROM_SCC+_SD', '-ext', 'MSXPi'] if HW == 'nextor'
               else ['-ext', 'ram2mb', '-ext', 'MSXPi'])
    write_script(script, dumps)

    log = []
    irc = Server(('0.0.0.0', IRC_PORT))
    threading.Thread(target=irc.serve_forever, daemon=True).start()
    alice = Player('Alice', ROOM, ['e4', 'Nf3'], 'resign', 4, log)
    bob = Player('Bob', None, ['d4'], 'draw', 2, log)
    alice.start()
    bob.start()

    env = dict(os.environ, MSXPI_HOME=str(home))
    server_log = (work / 'server.log').open('w')
    server = subprocess.Popen([sys.executable, '-u', 'msxpi-server.py'], env=env,
                              cwd=SOFTWARE / 'Server/Python/src', stdout=server_log,
                              stderr=subprocess.STDOUT)
    try:
        time.sleep(3)
        with (work / 'openmsx.log').open('w') as out:
            subprocess.run([OPENMSX, '-machine', 'Canon_V-25', *machine,
                            '-command', 'set renderer none', '-script', str(script)],
                           stdout=out, stderr=subprocess.STDOUT, timeout=600)
    finally:
        alice.done = bob.done = True
        server.terminate()
        server.wait()
        server_log.close()

    screens = {}
    for name in ('link', 'local', 'room-matched', 'room-end', 'lobby-matched',
                 'draw-offered', 'draw-agreed', 'final'):
        path = dumps / f'{name}.vram'
        if path.exists():
            screens[name] = screen_report(path.read_bytes())
            print(f'[{name}]', screens[name])
    print('\n'.join(log))
    (work / 'players.log').write_text('\n'.join(log))
    (work / 'irc.txt').write_text('\n'.join(' '.join(t) for t in irc.transcript))

    failures = []

    def check(name, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + name + (' - ' + str(detail) if detail and not ok else ''))
        if not ok:
            failures.append(name)

    s = screens.get
    check('link switched', s('link') and s('link')['status'] == 'LINK TCPIP', s('link'))
    check('local rules', s('local') and s('local')['moves'][:4] == ['E4', 'E5', 'NF3', ''], s('local'))
    check('local illegal refused', s('local') and 'ILLEGAL' in s('local')['status'], s('local'))
    a, b = alice.irc.peer, bob.irc.peer
    check('room paired, alice white', a.side is True and a.peer == 'MsxOne', (a.side, a.peer))
    check('room moves crossed', a.history[:4] == ['e4', 'e5', 'Nf3', 'Nc6'], a.history)
    check('room result on msx', s('room-end') and 'RESIGNED' in s('room-end')['status'], s('room-end'))
    check('lobby matched', b.peer == 'MsxOne' and b.side is True, (b.peer, b.side))
    check('lobby moves crossed', b.history[:2] == ['d4', 'd5'], b.history)
    check('draw offer shown', s('draw-offered') and 'OFFERS DRAW' in s('draw-offered')['status'],
          s('draw-offered'))
    check('draw agreed both sides', b.result == 'draw' and s('draw-agreed') and
          'DRAW' in s('draw-agreed')['status'], (b.result, s('draw-agreed')))
    check('no player errors', not alice.error and not bob.error, (alice.error, bob.error))
    print('artefacts in', work)
    irc.shutdown()
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
