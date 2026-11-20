"""PPOKER's live table on two emulated MSX Pis at once.

The unverified paths this covers:

  * the nine-seat table as the MSX actually draws it (seats, stacks, the
    board, my hole cards, the panel and the status line), and
  * J on the lobby, a room name and Return (join), including joining in the
    middle of a hand: the player is dealt in when the hand ends.

Two `msxpi-server.py` instances run on loopback, each with its own scratch
MSXPI_HOME and its own openMSX (Canon V-25 + 2 MB + MSXPi, MSX-DOS from the
server's drive A).  The first MSX hosts room T1 (`HOST A TABLE`), which also
starts the relay on port 5090.  Seven scripted players join that relay over
HTTP, the eighth is the second MSX.  Both MSXes press C when the relay sees
their turn, so a live hand reaches the flop with all nine seats seated.

The MSX screens are SCREEN 5, so the frames are read back from VRAM and
rendered with PPOKER's palette to work/poker-table-*/vram/*.png; the text is
decoded with PPOKER's own font for the checks.

    python poker_table_openmsx.py
"""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[1]
OPENMSX = os.environ.get(
    'OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.7.0/openmsx.exe')
PORTS = (5071, 5072)
RELAY_PORT = 5090
ROOM = 'T1'
BOTS = ['BOT%d' % i for i in range(1, 8)]
ANN, BOB = 'ANN', 'BOB'

# ppoker.c's palette, 3 bits per component.
PALETTE = [(0, 0, 0), (1, 0, 0), (0, 4, 1), (1, 6, 2), (5, 0, 0), (7, 1, 1),
           (3, 2, 0), (7, 4, 0), (2, 2, 2), (7, 2, 2), (6, 6, 0), (7, 7, 1),
           (0, 0, 3), (1, 1, 6), (4, 4, 4), (7, 7, 7)]
HAND_NAMES = ('HIGH CARD', 'PAIR', 'TWO PAIR', 'TRIPS', 'STRAIGHT', 'FLUSH',
              'FULL HOUSE', 'QUADS', 'STR FLUSH')
STATUS_X, STATUS_Y = 0, 205


# ---------------------------------------------------------------- screen text

def load_font():
    src = (SOFTWARE / 'Client/src/ppoker.c').read_text()
    font = {}
    for rows, char in re.findall(
            r'\{((?:0x[0-9A-F]{2},){6}0x[0-9A-F]{2})\}, /\* (.) \*/', src):
        font[tuple(int(v, 16) for v in rows.split(','))] = char
    return font


FONT = load_font()


def text_at(vram, x, y, count=41, background=0):
    """The text drawn at (x, y) with PPOKER's 6x7 glyphs, white pixels only."""
    out = ''
    for n in range(count):
        left = x + n * 6
        if left + 6 > 256:
            break
        rows = []
        for r in range(7):
            bits = 0
            for c in range(5):
                px = left + c
                byte = vram[(y + r) * 128 + px // 2]
                value = (byte >> 4) if px % 2 == 0 else (byte & 15)
                if value == 15:
                    bits |= 0x10 >> c
            rows.append(bits)
        out += FONT.get(tuple(rows), '?')
    return out.rstrip()


def seat_text(vram, index):
    x = (index % 3) * 64 + 3
    y = 10 + (index // 3) * 24
    # The glyph cells start two pixels inside the seat frame.
    return (text_at(vram, x - 1, y + 2, 10) + ' / ' +
            text_at(vram, x - 1, y + 11, 10)).strip()


def render(vram, path, scale=2):
    from PIL import Image
    image = Image.new('RGB', (256, 212))
    pixels = image.load()
    for y in range(212):
        row = vram[y * 128:(y + 1) * 128]
        for x in range(256):
            value = (row[x // 2] >> 4) if x % 2 == 0 else (row[x // 2] & 15)
            r, g, b = PALETTE[value]
            pixels[x, y] = (r * 255 // 7, g * 255 // 7, b * 255 // 7)
    image.resize((256 * scale, 212 * scale), Image.NEAREST).save(path)


# ---------------------------------------------------------------- the relay

def poker(command, nick, room=ROOM):
    payload = json.dumps({'cmd': command, 'nick': nick, 'room': room}).encode()
    request = Request('http://127.0.0.1:%d/poker' % RELAY_PORT, payload,
                      {'Content-Type': 'application/json'})
    try:
        with urlopen(request, timeout=5) as response:
            return bytes.fromhex(json.loads(response.read(16384))['packet'])
    except Exception:
        return None


def seat_of(packet, nick):
    if not packet or packet[4] != 1 or len(packet) != 256:
        return None
    for i in range(9):
        base = 64 + i * 16
        name = packet[base + 8:base + 14].split(b'\0')[0].decode('ascii', 'replace')
        if packet[base] & 1 and name == nick:
            return i
    return None


# ---------------------------------------------------------------- the MSXes

def tcl_string(text):
    return text.replace('\\', '\\\\').replace('"', '\\"').replace('\r', '\\r')


def write_script(path, port, work, dumps, index, follower):
    """A Tcl state machine: boot, PPOKER, lobby, host/join, dump, act, exit.

    The Python side leaves marker files in the work folder to sequence the
    two MSXes (bots seated, opponent joined, a hand on the flop, whose turn).
    """
    kids = ''
    if follower:
        kids = '''
proc start {} {
    waitlobby
}
proc waitlobby {} {
    # The status line at y=205 is drawn last and DOS never reaches it.
    if {[white 26240] > 10} {
        dump lobby
        waitbots
    } else { after time 1 waitlobby }
}
proc waitbots {} {
    if {[file exists "%(work)s/bots.txt"]} {
        type_via_keybuf "J"
        after time 2 joinprompt
    } else { after time 1 waitbots }
}
proc joinprompt {} {
    dump joinprompt
    type_via_keybuf "T"
    after time 1 {type_via_keybuf "1"}
    after time 2 {type_via_keybuf "\\r"}
    after time 14 joined
}
proc joined {} {
    dump table
    waithand
}
proc waithand {} {
    if {[file exists "%(work)s/midhand.txt"]} {
        after time 2 dump-hand
    } else { after time 1 waithand }
}
proc dump-hand {} {
    dump table-hand
    waitturn
}
proc waitturn {} {
    if {[file exists "%(work)s/turn-b.txt"]} {
        file delete "%(work)s/turn-b.txt"
        log "pressing C on my turn"
        type_via_keybuf "c"
        after time 4 afteraction
    } else { after time 0.5 waitturn }
}
''' % {'work': work.as_posix()}
    else:
        kids = '''
proc start {} {
    waitlobby
}
proc waitlobby {} {
    # The status line at y=205 is drawn last and DOS never reaches it.
    if {[white 26240] > 10} {
        dump lobby
        type_via_keybuf "H"
        after time 3 hostprompt
    } else { after time 1 waitlobby }
}
proc hostprompt {} {
    dump hostprompt
    type_via_keybuf "T"
    after time 1 {type_via_keybuf "1"}
    after time 2 {type_via_keybuf "\\r"}
    after time 14 hosted
}
proc hosted {} {
    dump table-empty
    set f [open "%(work)s/hosted.txt" w]
    close $f
    waitbots
}
proc waitbots {} {
    if {[file exists "%(work)s/bots.txt"]} { dump table-bots; waitjoin } else { after time 1 waitbots }
}
proc waitjoin {} {
    if {[file exists "%(work)s/joined.txt"]} { dump table-full; waithand } else { after time 1 waitjoin }
}
proc waithand {} {
    if {[file exists "%(work)s/midhand.txt"]} {
        after time 2 dump-hand
    } else { after time 1 waithand }
}
proc dump-hand {} {
    dump table-hand
    waitturn
}
proc waitturn {} {
    if {[file exists "%(work)s/turn-a.txt"]} {
        file delete "%(work)s/turn-a.txt"
        log "pressing C on my turn"
        type_via_keybuf "c"
        after time 4 afteraction
    } else { after time 0.5 waitturn }
}
''' % {'work': work.as_posix()}

    script = '''set save_settings_on_exit off
set msxpiserver_port %(port)d
set throttle on
set pause off
set renderer none
set power on
proc log {msg} {
    set f [open "%(work)s/client-%(index)d.log" a]
    puts $f "$msg"
    close $f
}
proc white {addr} {
    set n 0
    for {set i 0} {$i < 40} {incr i} {
        set b [debug read VRAM [expr {$addr + $i}]]
        if {($b >> 4) == 15} {incr n}
        if {($b & 15) == 15} {incr n}
    }
    return $n
}
proc dump {name} {
    set f [open "%(dumps)s/$name.vram" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block VRAM 0 32768]
    close $f
    log "dumped $name"
}
proc afteraction {} {
    dump after-action
    waitquit
}
proc waitquit {} {
    if {[file exists "%(work)s/quit.txt"]} { dump final; log "exit"; exit } else { after time 1 waitquit }
}
proc boot {} {
    set s ""
    catch {set s [get_screen]}
    if {[regexp {A[:>]} $s]} {
        log "DOS prompt, starting PPOKER"
        type_via_keybuf "PPOKER\\r"
        after time 8 start
    } else { after time 1 boot }
}
after time 300 {log "watchdog"; dump watchdog; exit}
after time 3 boot
%(kids)s''' % {'port': port, 'work': work.as_posix(), 'dumps': dumps.as_posix(),
               'index': index, 'kids': kids}
    path.write_text(script)


# ---------------------------------------------------------------- the players

class Driver(threading.Thread):
    """Seven relay players, plus turn signals for the two MSX players."""

    def __init__(self, work, log):
        super().__init__(daemon=True)
        self.work, self.log = work, log
        self.stop = threading.Event()
        self.error = None
        self.bot_seats = {}
        self.ann_seat = self.bob_seat = None
        self.midhand = False
        self.street = 0
        self.turn_since = {}
        self.signalled = {'a': False, 'b': False}
        self.final = {}

    def say(self, text):
        line = '%s %s' % (time.strftime('%H:%M:%S'), text)
        self.log.append(line)
        print(line, flush=True)

    def wait_for_ann(self):
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline and not self.stop.is_set():
            packet = poker('poll', ANN)
            seat = seat_of(packet, ANN)
            if seat is not None:
                self.ann_seat = seat
                return packet
            time.sleep(1)
        raise RuntimeError('the hosting MSX never joined room ' + ROOM)

    def run(self):
        try:
            self.wait_for_ann()
            self.say('ANN is seated %d' % (self.ann_seat + 1))
            deadline = time.monotonic() + 90
            while not (self.work / 'hosted.txt').exists() and time.monotonic() < deadline:
                time.sleep(0.5)
            if not (self.work / 'hosted.txt').exists():
                raise RuntimeError('the hosting MSX did not draw its table')
            for nick in BOTS:
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline and not self.stop.is_set():
                    packet = poker('join ' + ROOM, nick)
                    seat = seat_of(packet, nick)
                    if seat is not None:
                        self.bot_seats[nick] = seat
                        self.say('%s joined seat %d' % (nick, seat + 1))
                        break
                    time.sleep(1)
                else:
                    raise RuntimeError(nick + ' could not join')
            (self.work / 'bots.txt').write_text('ok\n')
            self.say('seven bots seated, waiting for the joining MSX')
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline and not self.stop.is_set():
                packet = poker('poll', ANN)
                self.bob_seat = seat_of(packet, BOB)
                if self.bob_seat is not None:
                    (self.work / 'joined.txt').write_text('ok\n')
                    self.say('BOB joined seat %d' % (self.bob_seat + 1))
                    break
                time.sleep(1)
            else:
                raise RuntimeError('the joining MSX never joined room ' + ROOM)
            self.play()
        except Exception as exc:
            self.error = exc
            self.say('ERROR ' + repr(exc))

    def play(self):
        while not self.stop.is_set():
            for nick in BOTS:
                packet = poker('poll', nick)
                if packet and packet[4] == 1 and (packet[7] & 1):
                    call = packet[14] | (packet[15] << 8)
                    poker('call' if call else 'check', nick)
            ann = poker('poll', ANN)
            bob = poker('poll', BOB)
            if ann and ann[4] == 1:
                self.ann_seat = seat_of(ann, ANN) or self.ann_seat
                self.note_turn('a', ann, self.ann_seat)
                if not self.midhand and 2 <= ann[6] <= 4 and seat_of(ann, BOB) is not None:
                    bob_seat = seat_of(ann, BOB)
                    if (ann[64 + self.ann_seat * 16] & 2) and (ann[64 + bob_seat * 16] & 2):
                        self.midhand = True
                        self.street = ann[6]
                        (self.work / 'midhand.txt').write_text('ok\n')
                        self.say('hand %d is on street %d, both MSXes dealt in'
                                 % (ann[8] | (ann[9] << 8), ann[6]))
                self.final['ann'] = ann
            if bob and bob[4] == 1:
                seat = seat_of(bob, BOB)
                if seat is not None:
                    self.bob_seat = seat
                self.note_turn('b', bob, self.bob_seat)
                self.final['bob'] = bob
            if self.midhand and not (self.work / 'quit.txt').exists():
                self.elapsed = getattr(self, 'elapsed', 0) + 1
                if self.elapsed >= 25:
                    (self.work / 'quit.txt').write_text('ok\n')
                    self.say('written quit.txt')
            time.sleep(1)

    def note_turn(self, who, packet, seat):
        """Leave turn-X.txt while the flags say it is that MSX's turn."""
        if seat is None:
            return
        mine = bool(packet[7] & 1)
        marker = self.work / ('turn-%s.txt' % who)
        if mine and not self.signalled[who]:
            marker.write_text('ok\n')
            self.signalled[who] = True
            self.turn_since[who] = time.monotonic()
        elif not mine:
            if marker.exists():
                marker.unlink()
            self.signalled[who] = False
            self.turn_since.pop(who, None)
        elif mine and time.monotonic() - self.turn_since.get(who, time.monotonic()) > 8:
            # The MSX normally acts in a second or two.  If it does not, act
            # for it so the rest of the scene (the flop) still happens.
            call = packet[14] | (packet[15] << 8)
            poker('call' if call else 'check', ANN if who == 'a' else BOB)
            self.say('acted for %s (%s)' % (ANN if who == 'a' else BOB,
                                            'call' if call else 'check'))
            self.signalled[who] = False
            self.turn_since.pop(who, None)


# ---------------------------------------------------------------- the run

def free_port(port):
    # No SO_REUSEADDR here: on Windows it lets a probe bind over a listener
    # that another process holds, which hides a stale relay on the port.
    with socket.socket() as probe:
        try:
            probe.bind(('127.0.0.1', port))
        except OSError:
            return False
    return True


def make_home(root, name):
    home = root / name
    (home / 'disks').mkdir(parents=True)
    shutil.copy(SOFTWARE / 'target/disks/msxpiboot.dsk', home / 'disks/msxpiboot.dsk')
    shutil.copy(SOFTWARE / 'target/ppoker.com', home / 'ppoker.com')
    subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy',
                    '../ppoker.com', 'msxpiboot.dsk:PPOKER.COM'],
                   cwd=home / 'disks', check=True, stdout=subprocess.DEVNULL)
    return home


def wait_started(servers, settle=3.0):
    """Give the servers time to bind; do not connect to them: a server takes
    the first connection for the MSX and does not survive a probe."""
    time.sleep(settle)
    return all(proc.poll() is None for proc in servers)


def main():
    for port in PORTS + (RELAY_PORT,):
        if not free_port(port):
            print('FAIL: port %d is already in use' % port)
            return 1
    (SOFTWARE.parent / 'work').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='poker-table-', dir=SOFTWARE.parent / 'work'))
    dumps = [work / ('vram-%d' % i) for i in range(2)]
    for path in dumps:
        path.mkdir()
    homes = [make_home(work, 'home%d' % i) for i in range(2)]
    for i in range(2):
        write_script(work / ('client-%d.tcl' % i), PORTS[i], work, dumps[i], i, follower=bool(i))

    servers, emulators, logs = [], [], []
    driver = Driver(work, [])
    try:
        for i in range(2):
            env = dict(os.environ, MSXPI_HOME=str(homes[i]), MSXPI_PORT=str(PORTS[i]),
                       POKER_NICK=ANN if i == 0 else BOB)
            if i:
                env['POKER_RELAY_URL'] = 'http://127.0.0.1:%d' % RELAY_PORT
            log = (work / ('server-%d.log' % i)).open('w')
            logs.append(log)
            servers.append(subprocess.Popen(
                [sys.executable, '-u', 'msxpi-server.py'], cwd=SOFTWARE / 'Server/Python/src',
                env=env, stdout=log, stderr=subprocess.STDOUT))
        time.sleep(3)
        if not wait_started(servers):
            raise RuntimeError('a server exited before the MSXes connected')
        driver.start()
        emu_log = (work / 'openmsx.log').open('w')
        logs.append(emu_log)
        for i in range(2):
            emulators.append(subprocess.Popen(
                [OPENMSX, '-machine', 'Canon_V-25', '-ext', 'ram2mb', '-ext', 'MSXPi',
                 '-script', str(work / ('client-%d.tcl' % i))],
                stdout=emu_log, stderr=subprocess.STDOUT))
        deadline = time.monotonic() + 420
        while any(proc.poll() is None for proc in emulators):
            if time.monotonic() > deadline:
                raise RuntimeError('emulators timed out')
            if driver.error:
                raise driver.error
            time.sleep(0.5)
        if driver.error:
            raise driver.error
    finally:
        driver.stop.set()
        for proc in emulators:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
        for proc in servers:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
        for log in logs:
            log.close()

    frames = [{}, {}]
    art = SOFTWARE.parents[2] / 'work/ppoker-art'
    art.mkdir(parents=True, exist_ok=True)
    for client, folder in enumerate(dumps):
        for path in sorted(folder.glob('*.vram')):
            frames[client][path.stem] = path.read_bytes()
            render(frames[client][path.stem], path.with_suffix('.png'))
            if path.stem in ('lobby', 'hostprompt', 'joinprompt', 'table-empty',
                             'table-bots', 'table-full', 'table', 'table-hand',
                             'after-action', 'final'):
                shutil.copy(path.with_suffix('.png'),
                            art / ('ppoker-c%d-%s.png' % (client, path.stem)))
                shutil.copy(path, art / ('ppoker-c%d-%s.vram' % (client, path.stem)))

    for client in range(2):
        for name, vram in frames[client].items():
            print('[client %d %s] status: %s' % (client, name, text_at(vram, STATUS_X, STATUS_Y)))
    for i in range(9):
        if 'table-full' in frames[0]:
            print('  seat %d: %s' % (i + 1, seat_text(frames[0]['table-full'], i)))

    failures = []

    def check(name, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else ' - %s' % (detail,)))
        if not ok:
            failures.append(name)

    a, b = frames
    lobby = a.get('lobby', b'')
    check('A lobby drawn', 'HOST A TABLE' in text_at(lobby, 24, 62, 20), text_at(lobby, 24, 62, 20))
    check('A nick shown', 'NICK:' in text_at(lobby, 24, 110, 20), text_at(lobby, 24, 110, 20))
    check('A host prompt', 'NEW ROOM AND RETURN' in text_at(a.get('hostprompt', b''), STATUS_X, STATUS_Y),
          text_at(a.get('hostprompt', b''), STATUS_X, STATUS_Y))
    hosted = a.get('table-empty', b'')
    check('A seated after HOST', 'SEAT 1' in text_at(hosted, 194, 12, 8), text_at(hosted, 194, 12, 8))
    check('A table header', 'LV1' in text_at(hosted, 0, 1, 20), text_at(hosted, 0, 1, 20))
    check('lone host waits for players', 'WAITING FOR PLAYERS' in text_at(hosted, STATUS_X, STATUS_Y),
          text_at(hosted, STATUS_X, STATUS_Y))

    full = a.get('table-full', b'')
    seats = ' '.join(seat_text(full, i) for i in range(9))
    print('  nine seats:', seats)
    check('nine seats occupied', all(nick in seats for nick in BOTS + [ANN, BOB]), seats)
    check('header says PL9', 'PL9' in text_at(full, 0, 1, 24), text_at(full, 0, 1, 24))
    check('A still seated', 'SEAT 1' in text_at(full, 194, 12, 8), text_at(full, 194, 12, 8))

    check('B lobby drawn', 'JOIN A TABLE' in text_at(b.get('lobby', b''), 24, 52, 20),
          text_at(b.get('lobby', b''), 24, 52, 20))
    check('B join prompt', 'ROOM NAME AND RETURN' in text_at(b.get('joinprompt', b''), STATUS_X, STATUS_Y),
          text_at(b.get('joinprompt', b''), STATUS_X, STATUS_Y))
    joined = b.get('table', b'')
    check('B seated after JOIN', 'SEAT 9' in text_at(joined, 194, 12, 8), text_at(joined, 194, 12, 8))
    bseats = ' '.join(seat_text(joined, i) for i in range(9))
    check('B sees the nine seats', all(nick in bseats for nick in BOTS + [ANN, BOB]), bseats)

    hand = a.get('table-hand', b'')
    check('hand reached the flop', driver.street >= 2, driver.street)
    check('my hand named', any(name in text_at(hand, 92, 144, 12) for name in HAND_NAMES),
          text_at(hand, 92, 144, 12))
    acted = a.get('after-action', b'')
    ann = driver.final.get('ann', b'')
    ann_seat = seat_of(ann, ANN)
    last = ann[64 + ann_seat * 16 + 1] if ann_seat is not None else 0
    check('C sent the action', last in (2, 3), 'last action %d' % last)
    for client, label in ((0, 'A'), (1, 'B')):
        log = (work / ('client-%d.log' % client)).read_text()
        check('%s pressed C on its turn' % label, 'pressing C on my turn' in log, log)
    check('no error on the status line', 'ERROR' not in text_at(acted, STATUS_X, STATUS_Y) and
          'BAD PACKET' not in text_at(acted, STATUS_X, STATUS_Y), text_at(acted, STATUS_X, STATUS_Y))
    check('no player error', not driver.error, driver.error)

    print('artefacts in', work)
    print('PNGs and VRAM in', art)
    if failures:
        print('FAILURES:', ', '.join(failures))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
