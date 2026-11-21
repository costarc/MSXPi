"""PPOKER heads-up, played to a champion on two emulated MSX Pis.

What poker_table_openmsx.py does not reach: the end of a tournament.  The
first MSX hosts room T2 with a tiny stack and fast blinds (POKERSTACK=60,
POKERLEVELSECS=20, POKERHANDDELAY=1 in its msxpi.ini), the second joins it
through the host's relay, and both press A (all in) every time it is their
turn until one of them has every chip.  Then it checks:

  * the relay reports one champion (stage 7, one player left, byte 249 set,
    the status line naming the winner),
  * each client's own packet has byte 249 = 1, and the loser's seat record a
    zero stack,
  * both MSXes drew it: the status line names the winner, the panel says
    OVER, and the loser's seat reads OUT.

It is built on poker_table_openmsx.py's helpers (servers, scratch homes, the
Tcl boot, VRAM text reading) and runs on its own ports, 5075,5076 and relay
5092, so both scripts can run at once.  --ports A,B / --relay-port N (or
POKER_TEST_PORTS / POKER_TEST_RELAY_PORT) and --art DIR work as there.

    python poker_champion_openmsx.py [--ports A,B] [--relay-port N] [--art DIR]
"""
import sys
import tempfile
import threading
import time
from pathlib import Path

import poker_table_openmsx as table
from poker_table_openmsx import (ANN, BOB, STATUS_X, STATUS_Y, seat_of, seat_text,
                                 text_at)

PORTS = (5075, 5076)
RELAY_PORT = 5092
ROOM = 'T2'
SETTINGS = {'POKERSTACK': 60, 'POKERLEVELSECS': 20, 'POKERHANDDELAY': 1}
STAGE_DONE = 7
# Every hand is all in from both sides, so it is decided at once unless the
# pot is split; at 60 chips and blinds from 10/20 a short run of splits is the
# worst case.  Past this many hands something is wrong.
MAX_HANDS = 30
# Seconds the MSXes get after the end to draw it before they dump and exit.
DRAW_SECONDS = 8


def poker(command, nick):
    return table.poker(command, nick, ROOM)


def stack_of(packet, seat):
    base = 64 + seat * 16
    return packet[base + 2] | (packet[base + 3] << 8)


def status_of(packet):
    return packet[208:248].split(b'\0')[0].decode('ascii', 'replace')


# ---------------------------------------------------------------- the MSXes

def write_script(path, port, work, dumps, index, follower):
    """Boot into PPOKER, host or join T2, then press A on every turn marker
    until quit.txt, dumping the table before the end and the final screen."""
    who = 'b' if follower else 'a'
    if follower:
        seat = '''
proc start {} { waitlobby }
proc waitlobby {} {
    # The status line at y=205 is drawn last and DOS never reaches it.
    if {[white 26240] > 10} { dump lobby; waithost } else { after time 1 waitlobby }
}
proc waithost {} {
    if {[file exists "%(work)s/hosted.txt"]} {
        type_via_keybuf "J"
        after time 2 roomprompt
    } else { after time 1 waithost }
}
proc roomprompt {} {
    dump joinprompt
    type_via_keybuf "T"
    after time 1 {type_via_keybuf "2"}
    after time 2 {type_via_keybuf "\\r"}
    after time 14 seated
}
proc seated {} { dump table; play }
'''
    else:
        seat = '''
proc start {} { waitlobby }
proc waitlobby {} {
    if {[white 26240] > 10} {
        dump lobby
        type_via_keybuf "H"
        after time 3 roomprompt
    } else { after time 1 waitlobby }
}
proc roomprompt {} {
    dump hostprompt
    type_via_keybuf "T"
    after time 1 {type_via_keybuf "2"}
    after time 2 {type_via_keybuf "\\r"}
    after time 14 seated
}
proc seated {} {
    dump table
    set f [open "%(work)s/hosted.txt" w]
    close $f
    play
}
'''
    play = '''
set presses 0
proc play {} {
    global presses
    if {[file exists "%(work)s/quit.txt"]} {
        dump final
        log "exit after $presses presses"
        exit
    } elseif {[file exists "%(work)s/turn-%(who)s.txt"]} {
        file delete "%(work)s/turn-%(who)s.txt"
        incr presses
        log "pressing A on my turn"
        if {$presses == 1} { after time 2 {dump first-allin} }
        type_via_keybuf "a"
        after time 3 play
    } else { after time 0.5 play }
}
'''
    kids = (seat + play) % {'work': work.as_posix(), 'who': who}
    path.write_text(table.tcl_prelude(port, work, dumps, index, watchdog=360) + kids)


# ---------------------------------------------------------------- the relay side

class Driver(threading.Thread):
    """Seats both MSXes, signals their turns, and ends the scene once the
    tournament is over and both MSXes have had time to draw it."""

    def __init__(self, work):
        super().__init__(daemon=True)
        self.work = work
        self.stop = threading.Event()
        self.error = None
        self.seats = {}
        self.signalled = {'a': False, 'b': False}
        self.turn_since = {}
        self.acted_for = {'a': 0, 'b': 0}
        self.hands = 0
        self.final = {}
        self.over_at = None

    def say(self, text):
        print('%s %s' % (time.strftime('%H:%M:%S'), text), flush=True)

    def seated(self, nick, deadline, viewer=None):
        while time.monotonic() < deadline and not self.stop.is_set():
            packet = poker('poll', viewer or nick)
            seat = seat_of(packet, nick)
            if seat is not None:
                return seat
            time.sleep(1)
        raise RuntimeError('%s never sat down in room %s' % (nick, ROOM))

    def run(self):
        try:
            self.seats[ANN] = self.seated(ANN, time.monotonic() + 180)
            self.say('ANN hosts %s in seat %d' % (ROOM, self.seats[ANN] + 1))
            self.seats[BOB] = self.seated(BOB, time.monotonic() + 150, viewer=ANN)
            self.say('BOB joined seat %d' % (self.seats[BOB] + 1))
            self.play()
        except Exception as exc:
            self.error = exc
            self.say('ERROR ' + repr(exc))

    def play(self):
        deadline = time.monotonic() + 240
        while not self.stop.is_set():
            if time.monotonic() > deadline:
                raise RuntimeError('no champion after 240 s (%d hands)' % self.hands)
            packets = {ANN: poker('poll', ANN), BOB: poker('poll', BOB)}
            for who, nick in (('a', ANN), ('b', BOB)):
                packet = packets[nick]
                if packet and packet[4] == 1:
                    self.final[nick] = packet
                    self.note_turn(who, nick, packet)
            ann = packets[ANN]
            if ann and ann[4] == 1:
                hand = ann[8] | (ann[9] << 8)
                if hand != self.hands:
                    self.hands = hand
                    self.say('hand %d: ANN %d, BOB %d' % (
                        hand, stack_of(ann, self.seats[ANN]), stack_of(ann, self.seats[BOB])))
                    if hand > MAX_HANDS:
                        raise RuntimeError('still no champion after %d hands' % MAX_HANDS)
                if ann[249] and self.over_at is None:
                    self.over_at = time.monotonic()
                    self.say('tournament over: %s' % status_of(ann))
            if self.over_at and time.monotonic() - self.over_at > DRAW_SECONDS:
                (self.work / 'quit.txt').write_text('ok\n')
                self.say('written quit.txt')
                return
            time.sleep(0.5)

    def note_turn(self, who, nick, packet):
        """turn-X.txt while the packet says it is that MSX's turn."""
        mine = bool(packet[7] & 1) and not packet[249]
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
        elif time.monotonic() - self.turn_since.get(who, time.monotonic()) > 10:
            # The MSX normally answers within a few seconds; if it does not,
            # go all in for it so the scene still ends.  Counted and reported.
            poker('allin', nick)
            self.acted_for[who] += 1
            self.say('went all in for %s' % nick)
            self.signalled[who] = False
            self.turn_since.pop(who, None)


# ---------------------------------------------------------------- the run

def main(argv=None):
    options = table.parse_options(argv, PORTS, RELAY_PORT,
                                  'PPOKER heads-up to a champion on two emulated MSXPis.')
    table.PORTS, table.RELAY_PORT = options.ports, options.relay_port
    print('ports %d,%d relay %d' % (options.ports + (options.relay_port,)), flush=True)
    for port in options.ports + (options.relay_port,):
        if not table.free_port(port):
            print('FAIL: port %d is already in use' % port)
            return 1
    (table.SOFTWARE.parent / 'work').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='poker-champion-', dir=table.SOFTWARE.parent / 'work'))
    dumps = [work / ('vram-%d' % i) for i in range(2)]
    for path in dumps:
        path.mkdir()
    homes = [table.make_home(work, 'home0', options.relay_port, SETTINGS),
             table.make_home(work, 'home1')]
    for i in range(2):
        write_script(work / ('client-%d.tcl' % i), options.ports[i], work, dumps[i], i,
                     follower=bool(i))

    driver = Driver(work)
    table.run_scene(work, homes, (ANN, BOB), driver, timeout=480)

    art = options.art or table.ART_ROOT / work.name
    frames = table.keep_frames(dumps, art, ('lobby', 'hostprompt', 'joinprompt', 'table',
                                            'first-allin', 'final'))
    for client in range(2):
        for name, vram in frames[client].items():
            print('[client %d %s] status: %s' % (client, name, text_at(vram, STATUS_X, STATUS_Y)))

    failures = []

    def check(name, ok, detail=''):
        print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else ' - %s' % (detail,)))
        if not ok:
            failures.append(name)

    ann, bob = driver.final.get(ANN, b''), driver.final.get(BOB, b'')
    seats = driver.seats
    ok = len(ann) == 256 and len(bob) == 256 and ANN in seats and BOB in seats
    check('both players have a final packet', ok, (len(ann), len(bob), seats))
    if not ok:
        print('FAIL poker_champion_openmsx: no final table')
        return 1
    stacks = {nick: stack_of(ann, seats[nick]) for nick in (ANN, BOB)}
    winner = max(stacks, key=stacks.get)
    loser = BOB if winner == ANN else ANN
    status = status_of(ann)
    print('  stacks %s, hands %d, status %r' % (stacks, driver.hands, status))
    check('relay: tournament over (stage 7)', ann[6] == STAGE_DONE, ann[6])
    check('relay: one player left', ann[23] == 1, ann[23])
    check('relay: one champion with every chip', stacks[winner] == 2 * SETTINGS['POKERSTACK']
          and stacks[loser] == 0, stacks)
    check('relay: status names the champion', '%s WINS THE TOURNAMENT' % winner in status, status)
    for nick, packet in ((ANN, ann), (BOB, bob)):
        check('%s packet byte 249 is 1' % nick, packet[249] == 1, packet[249])
        check("%s packet: loser's seat has a zero stack" % nick,
              stack_of(packet, seats[loser]) == 0 and packet[64 + seats[loser] * 16] & 16,
              stack_of(packet, seats[loser]))

    for client, label in ((0, 'A'), (1, 'B')):
        final = frames[client].get('final', b'')
        drawn = text_at(final, STATUS_X, STATUS_Y) if final else ''
        check('%s drew the end: status names %s' % (label, winner), winner in drawn and
              'WIN' in drawn, drawn)
        panel = text_at(final, 194, 68, 6) if final else ''
        check('%s drew OVER in the panel' % label, 'OVER' in panel, panel)
        lost = seat_text(final, seats[loser]) if final else ''
        check("%s drew the loser's seat as OUT" % label, loser in lost and 'OUT' in lost, lost)
        won = seat_text(final, seats[winner]) if final else ''
        print('  %s seats: %s | %s' % (label, won, lost))
        log = (work / ('client-%d.log' % client)).read_text()
        check('%s pressed A on its turn' % label, 'pressing A on my turn' in log, log)
    print('  went all in for an MSX that did not answer: %s' % driver.acted_for)
    check('no player error', not driver.error, driver.error)

    print('artefacts in', work)
    print('PNGs and VRAM in', art)
    ports = options.ports + (options.relay_port,)
    if failures:
        print('FAILURES:', ', '.join(failures))
        print('FAIL poker_champion_openmsx: %d checks failed (ports %d,%d relay %d)'
              % ((len(failures),) + ports))
        return 1
    print('PASS poker_champion_openmsx: %s won in %d hands (ports %d,%d relay %d)'
          % ((winner, driver.hands) + ports))
    return 0


if __name__ == '__main__':
    sys.exit(main())
