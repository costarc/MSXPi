"""End-to-end: PCHECKERS.COM on TCP/IP UNAPI in openMSX against a scripted
player, over IRC (the pchess IRC fixture).

The emulated MSX (Canon V-25 + 2 MB mapper + MSXPi, MSX-DOS 1) runs MSR I and
INL I, starts PCHECKERS, switches LINK to TCPIP in the ESC menu and joins room
"dama" with key 4. Alice, a plain IRC client speaking the PCH1 CK lines, is
already in #pchess-dama: she answers the MSX's HELLO, plays C3-D4 as white and
greets it. Then her IRC link drops, as an MSXPi server's can, so the MSX's
B6-A5 (black, board rotated) is lost. She comes back with the same nick and
sends SYNC 1: the MSX must resend B6-A5. Next she sends SYNC 3, as if her
D4-E5 had gone into a dead socket: the MSX must answer SYNC 2, and when the
move then arrives twice (both ends of a reconnect may ask) take it once. The
MSX reads and answers the chat in the TAB window, and finally Alice resigns.

The IRC fixture runs on this host; the MSX reaches it at 192.168.99.1 through
the Windows TAP (msxpi-tcpip-setup.ps1). Needs the MSXPi server port below and
6667 free.

    python pcheckers_tcpip_openmsx.py [path/to/pcheckers.com]
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
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(SOFTWARE / 'Server/Python/tests'))
from pchess_irc_fixture import Server  # noqa: E402
from pchess_tcpip_openmsx import chat_lines, tcl_string, text_at  # noqa: E402

OPENMSX = os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.7.0/openmsx.exe')
PROGRAM = Path(sys.argv[1] if len(sys.argv) > 1 else SOFTWARE / 'target/pcheckers.com')
IRC_PORT = 6667
MSXPI_PORT = 5043
ROOM = '#pchess-dama'
ESC, DOWN, RIGHT, UP, TAB = chr(27), chr(31), chr(28), chr(30), chr(9)

TIMELINE = [
    (20, 'MSR I\r'), (32, 'INL I\r'), (50, 'PCHECKERS\r'),
    # ESC menu: LINK is the third row; right toggles it, Return applies.
    (66, ESC), (68, DOWN * 2), (70, RIGHT), (71, '\r'), (75, 'dump:link'),
    (77, '4'), (79, 'dama\r'), (112, 'dump:matched'),
    # Black plays B6-A5 on the rotated board (the cursor starts on E3).
    (113, RIGHT), (113.5, RIGHT), (114, RIGHT), (114.5, DOWN), (115, DOWN), (115.5, DOWN), (116, ' '),
    (116.5, RIGHT), (117, UP), (117.5, ' '), (124, 'dump:moved'),
    (126, TAB), (130, 'dump:chat'), (131, 'hi alice\r'), (135, 'dump:chat-sent'), (137, ESC),
    (150, 'dump:synced'), (185, 'dump:end'), (187, 'quit'),
]


def write_script(path, dumps):
    lines = ['set save_settings_on_exit off', f'set msxpiserver_port {MSXPI_PORT}',
             'set speed 100', 'set power on',
             'proc dump {name} {',
             f'    set f [open "{dumps.as_posix()}/$name.vram" w]',
             '    fconfigure $f -translation binary',
             '    puts -nonewline $f [debug read_block VRAM 0 32768]',
             '    close $f', '}']
    for when, action in TIMELINE:
        if action == 'quit':
            lines.append(f'after time {when} {{exit}}')
        elif action.startswith('dump:'):
            lines.append(f'after time {when} {{dump {action[5:]}}}')
        else:
            lines.append(f'after time {when} {{type_via_keybuf "{tcl_string(action)}"}}')
    path.write_text('\n'.join(lines) + '\n')


class Alice(threading.Thread):
    """A bare IRC client that plays the white side of the PCH1 CK protocol,
    and drops and restores her link the way an MSXPi server's IRC does."""

    def __init__(self, log, irc):
        super().__init__(daemon=True)
        self.log, self.irc, self.heard, self.moves, self.syncs, self.error = log, irc, [], [], [], None
        self.done = False
        self.stage, self.since = 'hello', time.monotonic()
        self.connect()

    def connect(self):
        self.sock = socket.create_connection(('127.0.0.1', IRC_PORT))
        self.sock.settimeout(.5)
        self.send('NICK Alice')
        self.send('USER alice 0 * :alice')
        self.send('JOIN ' + ROOM)

    def send(self, line):
        self.sock.sendall((line + '\r\n').encode())

    def next(self, stage):
        self.log.append(f'[alice {stage}]')
        self.stage, self.since = stage, time.monotonic()

    def run(self):
        buffer = b''
        try:
            while not self.done:
                waited = time.monotonic() - self.since
                if self.stage == 'drop' and waited > 1:
                    self.sock.close()       # the nick is free at once: the MSX's move gets 401
                    self.sock, buffer = None, b''
                    self.next('away')
                    continue
                elif self.stage == 'away':
                    if ('MsxOne', 'Alice', 'PCH1 CK MOVE 1 b6a5') in self.irc.transcript:
                        self.connect()
                        self.next('rejoin')
                    else:
                        time.sleep(.1)
                    continue
                elif self.stage == 'played' and waited > 35:
                    self.send('PRIVMSG MsxOne :PCH1 CK RESIGN')
                    self.next('resigned')
                try:
                    buffer += self.sock.recv(4096)
                except socket.timeout:
                    continue
                while b'\r\n' in buffer:
                    line, buffer = buffer.split(b'\r\n', 1)
                    parts = line.decode().split(' ', 3)
                    if len(parts) == 3 and parts[1] == 'JOIN' and parts[0].startswith(':Alice!'):
                        if self.stage == 'rejoin':
                            # Back with the same nick: "I hold one move", as link_restored() says.
                            self.send('PRIVMSG MsxOne :PCH1 CK SYNC 1')
                            self.next('sync1')
                        continue
                    if len(parts) < 4 or parts[1] != 'PRIVMSG':
                        continue
                    sender, target, text = parts[0][1:].split('!')[0], parts[2], parts[3][1:]
                    self.log.append(f'{sender}->{target}: {text}')
                    if text == 'PCH1 CK HELLO' and self.stage == 'hello':
                        self.send(f'PRIVMSG {sender} :PCH1 CK HERE')
                        self.send(f'PRIVMSG {sender} :PCH1 CK MOVE 0 c3d4')
                        self.send(f'PRIVMSG {sender} :good luck msx')
                        self.next('drop')
                    elif text.startswith('PCH1 CK MOVE'):
                        self.moves.append(text)
                        if text == 'PCH1 CK MOVE 1 b6a5' and self.stage == 'sync1':
                            # As if D4-E5 had gone into a dead socket: claim three moves.
                            self.send('PRIVMSG MsxOne :PCH1 CK SYNC 3')
                            self.next('sync3')
                    elif text.startswith('PCH1 CK SYNC'):
                        self.syncs.append(text)
                        if text == 'PCH1 CK SYNC 2' and self.stage == 'sync3':
                            self.send('PRIVMSG MsxOne :PCH1 CK MOVE 2 d4e5')
                            self.send('PRIVMSG MsxOne :PCH1 CK MOVE 2 d4e5')
                            self.next('played')
                    elif not text.startswith('PCH1'):
                        self.heard.append(text)
        except Exception as exc:
            self.error = exc


def main():
    (SOFTWARE.parent / 'work').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='pcheckers-tcpip-', dir=SOFTWARE.parent / 'work'))
    home, dumps = work / 'home', work / 'vram'
    (home / 'disks').mkdir(parents=True)
    dumps.mkdir()
    shutil.copy(SOFTWARE / 'target/disks/msxpiboot.dsk', home / 'disks/msxpiboot.dsk')
    shutil.copy(SOFTWARE / 'target/disks/tools.dsk', home / 'disks/tools.dsk')
    (work / 'PCHESS.INI').write_bytes(b'IRCADDR=192.168.99.1\r\nIRCPORT=6667\r\nIRCNICK=MsxOne\r\n')
    shutil.copy(PROGRAM, work / 'pcheckers.com')
    for name, target in (('pcheckers.com', 'PCHECKERS.COM'), ('PCHESS.INI', 'PCHESS.INI')):
        subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', name,
                        f'home/disks/msxpiboot.dsk:{target}'], cwd=work, check=True,
                       stdout=subprocess.DEVNULL)
    script = work / 'pcheckers.tcl'
    write_script(script, dumps)

    irc = Server(('0.0.0.0', IRC_PORT))
    threading.Thread(target=irc.serve_forever, daemon=True).start()
    time.sleep(.5)
    log = []
    alice = Alice(log, irc)
    alice.start()

    env = dict(os.environ, MSXPI_HOME=str(home), MSXPI_PORT=str(MSXPI_PORT))
    server_log = (work / 'server.log').open('w')
    server = subprocess.Popen([sys.executable, '-u', 'msxpi-server.py'], env=env,
                              cwd=SOFTWARE / 'Server/Python/src', stdout=server_log,
                              stderr=subprocess.STDOUT)
    try:
        time.sleep(3)
        with (work / 'openmsx.log').open('w') as out:
            subprocess.run([OPENMSX, '-machine', 'Canon_V-25', '-ext', 'ram2mb', '-ext', 'MSXPi',
                            '-command', 'set renderer none', '-script', str(script)],
                           stdout=out, stderr=subprocess.STDOUT, timeout=600)
    finally:
        alice.done = True
        server.terminate()
        server.wait()
        server_log.close()
    print('\n'.join(log))

    def screen(name):
        path = dumps / f'{name}.vram'
        return path.read_bytes() if path.exists() else b'\0' * 32768

    failures = []

    def check(name, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + name + (' - ' + str(detail) if detail and not ok else ''))
        if not ok:
            failures.append(name)

    def status(vram):
        return text_at(vram, 8, 205)

    # The status line has moved on by the dump; the nick shows the link: MsxOne is
    # PCHESS.INI's, and the MSXPi server here would play relay rooms, not IRC.
    check('link switched', ('MsxOne', ROOM, 'PCH1 CK HELLO') in irc.transcript,
          status(screen('link')))
    matched = screen('matched')
    moves = [text_at(matched, 206, 41 + i * 9, 8) for i in range(2)]
    check('paired as black with the white move shown',
          text_at(matched, 206, 2, 8) == 'AS BLACK' and moves[0] == 'C3-D4',
          (text_at(matched, 206, 2, 8), moves, status(matched)))
    moved = screen('moved')
    moves = [text_at(moved, 206, 41 + i * 9, 8) for i in range(3)]
    check('own move played', moves[:2] == ['C3-D4', 'B6-A5'], moves)
    sent = [text for nick, to, text in irc.transcript if nick == 'MsxOne' and to == 'Alice']
    # The first copy went to a missing nick; the second answers her SYNC 1.
    check('move lost while alice was away, resent on SYNC',
          sent.count('PCH1 CK MOVE 1 b6a5') == 2 and 'PCH1 CK MOVE 1 b6a5' in alice.moves,
          (sent, alice.moves))
    check('SYNC 3 answered with SYNC 2', alice.syncs == ['PCH1 CK SYNC 2'], alice.syncs)
    synced = screen('synced')
    moves = [text_at(synced, 206, 41 + i * 9, 8) for i in range(4)]
    check('her lost move taken once', moves == ['C3-D4', 'B6-A5', 'D4-E5', ''], moves)
    check('not out of sync', 'SYNC' not in status(synced), status(synced))
    check('chat: greeting private', chat_lines(screen('chat')) == [('ALICE: GOOD LUCK MSX', 'private')],
          chat_lines(screen('chat')))
    check('chat: answer shown', chat_lines(screen('chat-sent'))[-1:] == [('YOU: HI ALICE', 'private')],
          chat_lines(screen('chat-sent')))
    check('chat: alice heard it', 'HI ALICE' in alice.heard, alice.heard)
    end = screen('end')
    check('resignation shown', 'RESIGNED' in status(end), status(end))
    check('no errors', not alice.error, alice.error)
    print('artefacts in', work)
    irc.shutdown()
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
